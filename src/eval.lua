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

local eval = {}

function eval.match_peg(peg, input, start)
   local results = { (lpeg.C(peg) * lpeg.Cp()):match(input, start) }
   local matchtext, pos = results[1], results[#results]
   if (not matchtext) then return false, 1; end
   assert(type(matchtext)=="string")
   assert(type(pos)=="number")
   return matchtext, pos
end

---------------------------------------------------------------------------------------------------
-- Reporting
---------------------------------------------------------------------------------------------------

local delta = 3

local function indent_(n)
   return string.rep(" ", n)
end

local function step_(indent, step, ...)
   local msg = string.format("%3d.", step[1])
   step[1] = step[1] + 1;
   msg = msg .. string.rep(".", indent-4)	    -- allow room for step #
   for _,v in ipairs({...}) do
      msg = msg .. v
   end
   return msg .. "\n"
end

local eval_exp;					    -- forward reference

local function report_(m, pos, a, input, start, indent, fail_output_only, step)
   start = start or 1
   local maxlen = 60
   local aname, apos, atext, asubs, grammar_name, rule1, _
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

local function eval_ref(a, input, start, gmr, source, env, indent, fail_output_only, step, msg)
   msg = msg .. indent_(indent) .. "REFERENCE: " .. parse.reveal_ast(a) .. "\n"
   local pat = cinternals.compile_ref(a, gmr, source, env)
   local name, pos, text, subs = common.decode_match(a)
   local m, pos = eval.match_peg(pat.peg, input, start) 

   msg = msg .. report_(m, pos, a, input, start, indent, fail_output_only, step)

   if not(m and fail_output_only) then
      -- descend into identifier's definition...
      if (not pat.ast) then
	 -- built-in identifier with no ast
	 msg = msg .. indent_(indent) .. "This identifier is a built-in RPL pattern\n"
      else
	 local pat = env[text]
	 assert(pat)
	 local rhs = pat.ast
	 if next(rhs)=="capture" then rhs = rhs.capture.subs[2]; end
	 msg = msg .. indent_(indent) .. "Explanation (definition): " .. reveal_ast_indented(rhs, indent) .. "\n"
	 local dm, dpos
	 dm, dpos, msg = eval_exp(rhs, input, start, gmr, source, env, indent+delta,
				  fail_output_only, step, msg)
      end
   end
   return m, pos, msg
end

local function eval_sequence(a, input, start, gmr, source, env, indent, fail_output_only, step, msg)
   msg = msg .. indent_(indent) .. "SEQUENCE: " .. parse.reveal_ast(a) .. "\n"
   
   local pat = cinternals.compile_sequence(a, gmr, source, env)
   local m, pos = eval.match_peg(pat.peg, input, start) 
   msg = msg .. report_(m, pos, a, input, start, indent, fail_output_only, step)

   if not(m and fail_output_only) then
      msg = msg .. indent_(indent) .. "Explanation:\n"

      local name, pos, text, subs = common.decode_match(a)
      -- sequences from the parser are always binary, i.e. there are exactly two subs.
      -- Regarding debugging... the failure of sub1 is fatal for a.
      local m, pos
      m, pos, msg =
	 eval_exp(subs[1], input, start, gmr, source, env, indent+delta,
		  fail_output_only, step, msg)

      if not m then return false, 1, msg; end	    -- Found the match error, so done.

      return eval_exp(subs[2], input, pos, gmr, source, env, indent+delta,
		      fail_output_only, step, msg)
   end
   return m, pos, msg
end

local function eval_choice(a, input, start, gmr, source, env, indent, fail_output_only, step, msg)
   msg = msg .. indent_(indent) .. "CHOICE: " .. parse.reveal_ast(a) .. "\n"
   
   local pat = cinternals.compile_choice(a, gmr, source, env)
   local m, pos
   m, pos = eval.match_peg(pat.peg, input, start)
   msg = msg .. report_(m, pos, a, input, start, indent, fail_output_only, step)

   if not(m and fail_output_only) then 
      msg = msg .. indent_(indent) .. "Explanation:\n"

      -- The parser returns only binary choice tokens, i.e. there are exactly two subs.
      -- Regarding debugging...
      -- if sub1 and sub2 fail, then a fails.
      indent = indent + delta;
      local name, pos, text, subs = common.decode_match(a)
      local m, pos
      m, pos, msg = eval_exp(subs[1], input, start, gmr, source, env, indent,
			     fail_output_only, step, msg)

      if m then
	 -- First alternative succeeded
	 return m, pos, msg
      else
	 msg = msg .. indent_(indent) .. "First option failed.  Proceeding to alternative.\n"
	 m, pos, msg = eval_exp(subs[2], input, start, gmr, source, env, indent,
				fail_output_only, step, msg)
	 if m then
	    -- Second alternative succeeded...
	    return m, pos, msg;
	 else
	    return false, 1, msg;
	 end -- if m (second alternative)
      end -- if m (first alternative)
   end
end

local function eval_quantified_exp(a, input, start, gmr, source, env, indent, fail_output_only, step, msg)
   local epeg, qpeg, append_boundary, qname, min, max = cinternals.process_quantified_exp(a, gmr, source, env)
   msg = msg .. step_(indent, step,
		      "QUANTIFIED EXP (",
		      (append_boundary and "tokenized/cooked): ") or "raw): ",
		      parse.reveal_ast(a))

   local m, pos = eval.match_peg(qpeg, input, start) 
   msg = msg .. report_(m, pos, a, input, start, indent, fail_output_only, step)

--   descend into quantified exp's structure here?
--   write_indent(indent+delta)
--   write("(EXPLANATION) BASE EXP: ", parse.reveal_ast(a[3]), "\n")
--   ...

   return m, pos, msg
end

local function eval_literal(a, input, start, gmr, source, env, indent, fail_output_only, step, msg)
   msg = msg .. step_(indent, step, "LITERAL: ", parse.reveal_ast(a))
   local pat = cinternals.compile_literal(a)
   local name, pos, text, subs = common.decode_match(a)
   local m, pos = eval.match_peg(pat.peg, input, start)
   msg = msg .. report_(m, pos, a, input, start, indent, fail_output_only, step)
   return m, pos, msg
end

local function eval_charset(a, input, start, gmr, source, env, indent, fail_output_only, step, msg)
   local name, pos, text, subs = common.decode_match(a)
   msg = msg .. step_(indent, step,
		      "CHARACTER SET: ",
		      parse.reveal_ast(a),
		      (name=="range" and " (a character range)") or (" (a set of " .. #subs .. " characters)"))
   local pat = cinternals.compile_charset(a, gmr, source, env)
   local m, pos = eval.match_peg(pat.peg, input, start) 
   msg = msg .. report_(m, pos, a, input, start, indent, fail_output_only, step)
   return m, pos, msg
end

local function eval_named_charset(a, input, start, gmr, source, env, indent, fail_output_only, step, msg)
   msg = msg .. step_(indent, step, "NAMED CHARSET: ", parse.reveal_ast(a))
   local pat = cinternals.compile_named_charset(a, gmr, source, env)
   local m, pos = eval.match_peg(pat.peg, input, start)
   msg = msg .. report_(m, pos, a, input, start, indent, fail_output_only, step)
   return m, pos, msg
end

local function eval_predicate(a, input, start, gmr, source, env, indent, fail_output_only, step, msg)
   msg = msg .. step_(indent, step, "PREDICATE: ", parse.reveal_ast(a))
   
   local pat = cinternals.compile_predicate(a, gmr, source, env)
   local m, pos = eval.match_peg(pat.peg, input, start)
   msg = msg .. report_(m, pos, a, input, start, indent, fail_output_only, step)

   if not(m and fail_output_only) then
      -- descend into exp
      local name, pos, text, subs = common.decode_match(a)
      msg = msg .. indent_(indent) .. "Explanation (EXPRESSION): " .. parse.reveal_ast(a) ..  "\n"
      local dm, dpos
      dm, dpos, msg = eval_exp(subs[2], input, start, gmr, source, env, indent+delta,
				 fail_output_only, step, msg)
   end
   -- We return the start position to indicate that the predicate did not consume any input. 
   return m, start, msg
end

local function eval_grammar(a, input, start, gmr, source, env, indent, fail_output_only, step, msg)
   msg = msg .. step_(indent, step, "GRAMMAR:") .. indent_(indent) .. reveal_ast_indented(a, indent) .. "\n"
   local name, pat = cinternals.compile_grammar_rhs(a, gmr, source, env)
   local m, pos = eval.match_peg(pat.peg, input, start)
   msg = msg .. report_(m, pos, a, input, start, indent, fail_output_only, step)
   -- How to descend into the definition of a grammar?
   return m, pos, msg
end

local function eval_raw_exp(a, input, start, gmr, source, env, indent, fail_output_only, step, msg)
   return eval_exp(a.raw_exp.subs[1], input, start, gmr, source, env, indent, fail_output_only, step, msg)
end

local function eval_capture(a, input, start, gmr, source, env, indent, fail_output_only, step, msg)
   return eval_exp(a.capture.subs[2], input, start, gmr, source, env, indent, fail_output_only, step, msg)
end

eval_exp = function(ast, input, start, gmr, source, env, indent, fail_output_only, step, msg)
      local functions = {"eval_exp";
			 raw_exp=eval_raw_exp;
			 capture=eval_capture;
			 choice=eval_choice;
			 sequence=eval_sequence;
			 predicate=eval_predicate;
			 ref=eval_ref;
			 literal=eval_literal;
			 named_charset=eval_named_charset;
			 charset=eval_charset;
			 new_quantified_exp=eval_quantified_exp;
			 new_grammar=eval_grammar;
		   }
   return common.walk_ast(ast, functions, input, start, gmr, source, env, indent, fail_output_only, step, msg)
end

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
   -- sigh.  time to implement real closures.

   assert(pattern.is(pat), "Internal error: eval.eval was not passed a compiled pattern: " .. tostring(pat))
   return eval_exp(pat.ast, input, start, gmr, source, env, indent, fail_output_only, step, "")
end


return eval
