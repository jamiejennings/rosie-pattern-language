---- -*- Mode: Lua; -*-                                                                           
----
---- eval.lua        Step by step evaluation of Rosie patterns
----
---- © Copyright IBM Corporation 2016.
---- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
---- AUTHOR: Jamie A. Jennings


-- N.B.  The evaluation functions utilize both the compiled lpeg patterns that the 'match'
-- function uses (when an engine runs) and also the AST that created those compiled lpeg
-- patterns.  The AST is needed in order to step through the evaluation process.  Therefore, these
-- eval functions MUST BE SEMANTICALLY EQUIVALENT to their counterparts in the compiler.  (In
-- other words, the interpreter called 'eval' should have the same semantics as the compiler.)

local parse = require "parse"
local compile = require "compile"
local cinternals = compile.cinternals
local common = require "common"
require "list"

local eval = {}

function eval.match_peg(peg, input, start)
   local results = { (lpeg.C(peg) * lpeg.Cp()):match(input, start) }
   local matchtext, pos = results[1], results[#results]
   if (not matchtext) then return false, start; end
   assert(type(matchtext)=="string")
   assert(type(pos)=="number")
   return matchtext, pos
end

---------------------------------------------------------------------------------------------------
-- Reporting
---------------------------------------------------------------------------------------------------

local delta = 3

local function indent_(n)
   return string.rep(" ", delta*n)
end

-- local function step_(indent, step, ...)
--    local msg = string.format("%3d.", step[1])
--    step[1] = step[1] + 1;
--    msg = msg .. string.rep(".", indent-4)	    -- allow room for step #
--    for _,v in ipairs({...}) do
--       msg = msg .. v
--    end
--    return msg
-- end

local eval_exp;					    -- forward reference

local function report_(m, pos, a, input, start, indent, fail_output_only, step)
   start = start or 1
   local maxlen = 60
   if m then
      local fmt = "Matched %q (against input %q"
      if (start+maxlen) < #input then fmt = fmt .. " ..."; end
      fmt = fmt .. ")\n"
      return indent_(indent) .. string.format(fmt,
					      input:sub(start,pos-1),
					      input:sub(start, start+maxlen))
   else
      local fmt = "FAILED to match against input %q"
      if (start+maxlen) < #input then fmt = fmt .. " ..."; end
      fmt = fmt .. "\n"
      return indent_(indent) .. string.format(fmt, input:sub(start, start+maxlen))
   end
end

local function new_report_(m, pos, a, input, start, indent, fail_output_only, step)
   start = start or 1
   if m then return {status='match', start=start, ['end']=pos}
   else return {status='fail', start=start}; end
end

local function reveal_ast_indented(a, indent)
   -- grammars are revealed across multiple lines, so we must replace newlines
   -- in the value returned by 'reveal' with newline+indent
   local s = parse.reveal_ast(a)
   return s:gsub("\n", "\n"..string.rep(" ", indent))
end

---------------------------------------------------------------------------------------------------
-- Eval (debugging capability for matching)
---------------------------------------------------------------------------------------------------

-- APPROACH: Each AST node should (where appropriate) be evaluated using its PEG first.  If it
-- matches and we're doing fail_output_only, then we simply move on without writing any output.
-- If it matches and we're doing the full eval, we then descend into the definition of the node
-- and try to match each piece.

local function eval_ref(a, input, start, gmr, source, env, indent, fail_output_only, step)
   local pat = cinternals.compile_ref(a, gmr, source, env)
   local name, pos, text, subs = common.decode_match(a)
   local m, pos = eval.match_peg(pat.peg, input, start) 

   local trace = {name="REFERENCE", expression=parse.reveal_ast(a),
		  result=new_report_(m, pos, a, input, start, indent, fail_output_only, step)}

   if not(m and fail_output_only) then
      -- descend into identifier's definition...
      if (not pat.ast) then
	 -- built-in identifier with no ast
	 trace.explanation = {name="PRIMITIVE", trace.expression, trace.result}
      else
	 local pat = env[text]
	 assert(pat)
	 local rhs = pat.ast
	 if next(rhs)=="capture" then rhs = rhs.capture.subs[2]; end
	 local dm, dpos, t
	 dm, dpos, t = eval_exp(rhs, input, start, gmr, source, env, indent+delta,
				  fail_output_only, step)
	 trace.explanation = {t}
      end
   end
   return m, pos, trace
end

local function eval_sequence(a, input, start, gmr, source, env, indent, fail_output_only, step)
   local pat = cinternals.compile_sequence(a, gmr, source, env)
   local m, pos = eval.match_peg(pat.peg, input, start) 
   local trace = {name="SEQUENCE", expression=parse.reveal_ast(a),
		  result=new_report_(m, pos, a, input, start, indent, fail_output_only, step)}

   if not(m and fail_output_only) then
      local name, pos, text, subs = common.decode_match(a)
      -- sequences from the parser are always binary, i.e. there are exactly two subs.
      -- Regarding debugging... the failure of sub1 is fatal for a.
      local m, pos, t
      m, pos, t =
	 eval_exp(subs[1], input, start, gmr, source, env, indent+delta,
		  fail_output_only, step)
      trace.explanation = {t}
      if not m then return false, 1, trace; end	    -- Found the match error, so done.
      m, pos, t = eval_exp(subs[2], input, pos, gmr, source, env, indent+delta,
			   fail_output_only, step)
      table.insert(trace.explanation, t)
      return m, pos, trace
   end
   return m, pos, trace
end

local function eval_choice(a, input, start, gmr, source, env, indent, fail_output_only, step)
   local pat = cinternals.compile_choice(a, gmr, source, env)
   local m, pos
   m, pos = eval.match_peg(pat.peg, input, start)
   local trace = {name="CHOICE", expression=parse.reveal_ast(a), 
		  result=new_report_(m, pos, a, input, start, indent, fail_output_only, step)}

   if not(m and fail_output_only) then 
      -- The parser returns only binary choice tokens, i.e. there are exactly two subs.
      -- Regarding debugging...
      -- if sub1 and sub2 fail, then a fails.
      indent = indent + delta;
      local name, pos, text, subs = common.decode_match(a)
      local m, pos, t
      m, pos, t = eval_exp(subs[1], input, start, gmr, source, env, indent,
			       fail_output_only, step)

      trace.explanation = {t}
      if m then -- First alternative succeeded
	 return m, pos, trace
      else
	 m, pos, t = eval_exp(subs[2], input, start, gmr, source, env, indent,
			      fail_output_only, step)
	 table.insert(trace.explanation, t)
	 if m then -- Second alternative succeeded...
	    return m, pos, trace;
	 else
	    return false, 1, trace;
	 end -- if m (second alternative)
      end -- if m (first alternative)
   end
end

local function eval_quantified_exp(a, input, start, gmr, source, env, indent, fail_output_only, step)
   if start==0 then start=1; end
   local epeg, qpeg, append_boundary, qname, min, max = cinternals.process_quantified_exp(a, gmr, source, env)
   local m, pos = eval.match_peg(qpeg, input, start) 
   local trace = {name="QUANTIFIED EXP",
		  expression=(append_boundary and "(tokenized/cooked): " or "(raw): ") .. parse.reveal_ast(a),
		  result=new_report_(m, pos, a, input, start, indent, fail_output_only, step)}
   trace.bounds = {min=min, max=max, boundary=append_boundary}
   if (not m) or (not fail_output_only) then
   local _, _, _, subs = common.decode_match(a)
   local revealed_ast = parse.reveal_ast(subs[1])
      local i = start
      local substep = 1
      local mm, mpos = eval.match_peg(epeg, input, i)
      -- Look for the first occurrence of pattern
      local explanation = {{name="BASE EXP", expression=revealed_ast,
			    result=new_report_(mm, mpos, subs[1], input, i, 0, fail_output_only, step)}}
      i = mpos
      while mm do
	 if max and (substep==max) then break; end
	 substep = substep + 1
	 -- Look for boundary
	 if append_boundary then
	    mm, mpos = eval.match_peg(common.boundary, input, i)
	    table.insert(explanation, {name="BASE EXP", expression=revealed_ast,
				       result=new_report_(mm, mpos, subs[1], input, i, 0, fail_output_only, step)})
	    if not mm then break; end -- fail
	    i = mpos
	 end
	 -- Look for next occurrence of pattern
	 mm, mpos = eval.match_peg(epeg, input, i)
	 table.insert(explanation, {name="BASE EXP", expression=revealed_ast,
				    result=new_report_(mm, mpos, subs[1], input, i, 0, fail_output_only, step)})
	 i = mpos
      end -- while
      trace.explanation = explanation
   end -- if explanation needed
   return m, pos, trace
end

local function eval_literal(a, input, start, gmr, source, env, indent, fail_output_only, step)
   local pat = cinternals.compile_literal(a)
   local name, pos, text, subs = common.decode_match(a)
   local m, pos = eval.match_peg(pat.peg, input, start)
   local trace = {name="LITERAL", expression=parse.reveal_ast(a),
		  result=new_report_(m, pos, a, input, start, indent, fail_output_only, step)}
   return m, pos, trace
end

local function eval_charset(a, input, start, gmr, source, env, indent, fail_output_only, step)
   local name, pos, text, subs = common.decode_match(a)
   local pat = cinternals.compile_charset(a, gmr, source, env)
   local m, pos = eval.match_peg(pat.peg, input, start) 
   local trace = {name="CHARACTER SET", expression=parse.reveal_ast(a),
		  result=new_report_(m, pos, a, input, start, indent, fail_output_only, step)}
   return m, pos, trace
end

local function eval_charlist(a, input, start, gmr, source, env, indent, fail_output_only, step)
   local name, pos, text, subs = common.decode_match(a)
   local pat = cinternals.compile_charlist(a, gmr, source, env)
   local m, pos = eval.match_peg(pat.peg, input, start) 
   local trace = {name="CHARACTER SET", expression=parse.reveal_ast(a),
		  result=new_report_(m, pos, a, input, start, indent, fail_output_only, step)}
   return m, pos, trace
end

local function eval_range(a, input, start, gmr, source, env, indent, fail_output_only, step)
   local name, pos, text, subs = common.decode_match(a)
   local pat = cinternals.compile_range_charset(a, gmr, source, env)
   local m, pos = eval.match_peg(pat.peg, input, start) 
   local trace = {name="CHARACTER SET", expression=parse.reveal_ast(a),
		  result=new_report_(m, pos, a, input, start, indent, fail_output_only, step)}
   return m, pos, trace
end

local function eval_named_charset(a, input, start, gmr, source, env, indent, fail_output_only, step)
   local pat = cinternals.compile_named_charset(a, gmr, source, env)
   local m, pos = eval.match_peg(pat.peg, input, start)
   local trace = {name="NAMED CHARSET", expression=parse.reveal_ast(a),
		  result=new_report_(m, pos, a, input, start, indent, fail_output_only, step)}
   return m, pos, trace
end

local function eval_predicate(a, input, start, gmr, source, env, indent, fail_output_only, step)
   local pat = cinternals.compile_predicate(a, gmr, source, env)
   local m, pos = eval.match_peg(pat.peg, input, start)
   local trace = {name="PREDICATE", expression=parse.reveal_ast(a),
		  result=new_report_(m, pos, a, input, start, indent, fail_output_only, step)}
   if not(m and fail_output_only) then
      -- descend into exp
      local name, pos, text, subs = common.decode_match(a)
      local explanation = { parse.reveal_ast(a) }
      local dm, dpos, t
      dm, dpos, t = eval_exp(subs[2], input, start, gmr, source, env, indent+delta,
			     fail_output_only, step)
      trace.explanation = {t}
   end
   -- We return the start position to indicate that the predicate did not consume any input. 
   return m, start, trace
end

local function eval_grammar(a, input, start, gmr, source, env, indent, fail_output_only, step)
   local name, pat = cinternals.compile_grammar_rhs(a, gmr, source, env)
   local m, pos = eval.match_peg(pat.peg, input, start)
   local trace = {name="GRAMMAR", expression=parse.reveal_ast(a),
		  result=new_report_(m, pos, a, input, start, indent, fail_output_only, step)}
   -- How to descend into the definition of a grammar?
   return m, pos, trace
end

local function eval_raw_exp(a, input, start, gmr, source, env, indent, fail_output_only, step)
   return eval_exp(a.raw_exp.subs[1], input, start, gmr, source, env, indent, fail_output_only, step)
end

local function eval_capture(a, input, start, gmr, source, env, indent, fail_output_only, step)
   return eval_exp(a.capture.subs[2], input, start, gmr, source, env, indent, fail_output_only, step)
end

eval_exp = function(ast, input, start, gmr, source, env, indent, fail_output_only, step)
      local functions = {"eval_exp";
			 raw_exp=eval_raw_exp;
			 capture=eval_capture;
			 choice=eval_choice;
			 sequence=eval_sequence;
			 predicate=eval_predicate;
			 ref=eval_ref;
			 literal=eval_literal;
			 named_charset=eval_named_charset;
			 charlist=eval_charlist;
			 range=eval_range;
			 charset=eval_charset;
			 new_quantified_exp=eval_quantified_exp;
			 new_grammar=eval_grammar;
		   }
   return common.walk_ast(ast, functions, input, start, gmr, source, env, indent, fail_output_only, step)
end

function eval.trace_tostring(trace, indent, str)
   indent = indent or 0
   str = str or ""
   local name, exp, result = trace.name, trace.expression, trace.result
   str = str .. string.format("%s%s: %s\n", indent_(indent), name, exp)
   if result then
      if result.status=="match" then
	 str = str .. string.format("%s%s from %d to %d (length=%d)\n",
				    indent_(indent), result.status, result.start, result['end'],
				    result['end']-result.start)
      elseif result.status=="fail" then
	 str = str .. string.format("%s%s at %d\n", indent_(indent), result.status, result.start)
      else
	 error("Expect match or fail.  Received: " .. tostring(result.status))
      end
   end
   if name=="QUANTIFIED EXP" then
      local bounds = trace.bounds
      local max = bounds.max and tostring(bounds.max) or "unlimited"
      str = str ..
	 string.format(
	 "%sThe base expression must repeat at least %d and at most %s times, with %s boundary between each repetition\n", 
	 indent_(indent), bounds.min, max, bounds.boundary and "a" or "no")
   end
   if trace.explanation then
      for _, e in ipairs(trace.explanation) do
	 str = eval.trace_tostring(e, indent+1, str);
      end
   end
   return str
end

local function flatten1(trace, NAME)
   if not trace then return nil; end
   local new = {}; for k,v in pairs(trace) do new[k]=v; end
   if trace.name==NAME then
      local c1, c2 = trace.explanation[1], trace.explanation[2]
      if (not c2) or (c2.name~=NAME) then
	 new.explanation = {flatten1(c1, NAME), flatten1(c2, NAME)}
      else -- c2 is also NAME, so here is an opportunity to flatten
	 new.explanation = {flatten1(c1, NAME)}
	 local f = flatten1(c2, NAME)
	 if f.explanation then
	    for _, item in ipairs(f.explanation) do
	       table.insert(new.explanation, item)
	    end
	 end
      end
      return new
   else
      if new.explanation then
	 new.explanation = map(function(t) return flatten1(t, NAME) end, new.explanation)
      end
      return new
   end
end

local function flatten_trace(trace)
   return flatten1(flatten1(trace, "CHOICE"), "SEQUENCE")
end

-- function print_trace(trace)
--    print(trace_tostring(trace))
-- end

---------------------------------------------------------------------------------------------------
-- Interface to eval capability
---------------------------------------------------------------------------------------------------

function eval.eval(pat, input, start, env, fail_output_only)
   -- if fail_output_only is true, then we are using "eval" to explain a syntax error, not to dump
   -- a full trace of the entire matching process
   assert(type(input)=="string" and (not env or type(env)=="table"))
   start = start or 1
   local indent = 5				  -- need to leave room for the step number "%3d."
   local step = {1};

   -- N.B. source will be nil (below) when pattern_EXP_to_grep_pattern is used, so the compiler and
   -- parser cannot explain errors. and it will think there are errors... probably because the
   -- pattern_EXP_to_grep_pattern function uses a temporary environment to define p and q...
   -- sigh.  it is time to implement real closures.

   assert(pattern.is(pat), "Internal error: eval.eval was not passed a compiled pattern: " .. tostring(pat))
   return eval_exp(pat.ast, input, start, gmr, source, env, indent, fail_output_only, step)
end


return eval
