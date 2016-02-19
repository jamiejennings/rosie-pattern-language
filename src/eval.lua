---- -*- Mode: Lua; -*- 
----
---- eval.lua        Step by step evaluation of Rosie patterns
----
---- (c) 2016, Jamie A. Jennings
----

-- N.B.  The evaluation functions utilize both the compiled lpeg patterns that the 'match'
-- function uses (when an engine runs) and also the AST that created those compiled lpeg
-- patterns.  The AST is needed in order to step through the evaluation process.  Therefore, these
-- eval functions MUST BE SEMANTICALLY EQUIVALENT to their counterparts in the compiler.  (In
-- other words, the interpreter called 'eval' should have the same semantics as the compiler.)

local compile = require "compile"
local cinternals = compile.cinternals
local eval = {}

local P, V, C, S, R, Ct, Cg, Cp, Cc, Cmt =
   lpeg.P, lpeg.V, lpeg.C, lpeg.S, lpeg.R, lpeg.Ct, lpeg.Cg, lpeg.Cp, lpeg.Cc, lpeg.Cmt

local locale = lpeg.locale()

----------------------------------------------------------------------------------------
-- Eval (debugging capability for matching)
----------------------------------------------------------------------------------------

-- Wednesday, January 27, 2016
-- NEW APPROACH:
-- Each AST node should (where appropriate) be evaluated using its PEG first.  If it matches and
-- we're doing the full eval, we then descend into the definition of the node and try to match
-- each piece.  If it matches and we're doing fail_output_only, then we simply move on without
-- writing any output.

local delta = 3

local function write(...)
   io.write(...)
end

local function write_indent(n)
   write(string.rep(" ", n))
end

local function write_step(indent, step, ...)
   write(string.format("%3d.", step[1]))
   step[1] = step[1] + 1;
   write(string.rep(".", indent-4))		    -- allow room for step
   write(...)
   write("\n")
end

local eval_exp;					    -- forward reference

local function eval_report(m, pos, a, input, start, indent, fail_output_only, step)
   start = start or 1
   local maxlen = 60
   -- a lot of processing just so that we can show a grammar in a nice way
   local aname, apos, atext, asubs, asubidx, grammar_name, rule1, _

--   if type(a)=="table" then
--      aname, apos, atext, asubs, asubidx = common.decode_match(a)
--      if aname=="grammar_" and asubs and asubs[asubidx] then
--         _, rule1 = next(asubs[asubidx])
--         grammar_name = rule1 and rule1[1] and rule1[1].identifier and rule1[1].identifier.text
--      end
--   end

--   local evaluating = (type(a)=="string" and a)
--                      or (aname=="grammar_" and "grammar "..grammar_name)
--                      or parse.reveal_ast(a);

   if m then
      local fmt = "Matched %q (against input %q"
      if (start+maxlen) < #input then fmt = fmt .. " ..."; end
      fmt = fmt .. ")\n"

      write_indent(indent)
      write(string.format(fmt,
			  input:sub(start,pos-1),
			  input:sub(start, start+maxlen)))
   else
      local fmt = "FAILED to match against input %q"
      if (start+maxlen) < #input then fmt = fmt .. " ..."; end
      fmt = fmt .. "\n"

      write_indent(indent)
      write(string.format(fmt, input:sub(start, start+maxlen)))
   end
end

local function eval_group(a, input, start, raw, gmr, source, env, indent, fail_output_only, step)
   local name, pos, text, subs, subidx = common.decode_match(a)
   if name=="raw" then raw=true;
   elseif name=="cooked" then raw=false;
   end
   assert(subs[subidx] and not subs[subidx+1])	    -- always one sub
   local msg = (raw and "RAW") or ""
   write_indent(indent)
   write("GROUP: ", parse.reveal_ast(a), "\n");

   local pat = cinternals.compile_group(a, raw, gmr, source, env)
   local m, pos = compile.match_peg(Ct(pat.peg), input, start) 
   eval_report(m, pos, a, input, start, indent, fail_output_only, step)

   if not (m and fail_output_only) then
      write_indent(indent)
      write("Explanation:\n")
      local m, pos = eval_exp(subs[subidx], input, start, raw, gmr, source, env, indent+delta,
      fail_output_only, step)
   end

   return m, pos
end

local function reveal_ast_indented(a, indent)
   -- grammars are revealed across multiple lines, so we must replace newlines
   -- in the value returned by 'reveal' with newline+indent
   local s = parse.reveal_ast(a)
   return s:gsub("\n", "\n"..string.rep(" ", indent))
end

local function eval_identifier(a, input, start, raw, gmr, source, env, indent, fail_output_only, step)
   write_indent(indent)
   write("IDENTIFIER: ", parse.reveal_ast(a), "\n")
   local pat = cinternals.compile_identifier(a, raw, gmr, source, env)
   local m, pos = compile.match_peg(Ct(pat.peg), input, start) 

   eval_report(m, pos, a, input, start, indent, fail_output_only, step)

   if not(m and fail_output_only) then
      -- descend into identifier's definition...
      if type(pat.ast)~="table" then
	 -- built-in identifier with no ast
	 write_indent(indent)
	 write("This identifier is a built-in RPL pattern\n")
      else
	 -- identifier defined by user, so has an ast
	 write_indent(indent)
	 write("Explanation (identifier's definition): ", reveal_ast_indented(pat.ast, indent), "\n")
	 local dm, dpos = eval_exp(pat.ast, input, start, raw, gmr, source, env, indent+delta,
				   fail_output_only, step)
      end
   end
   return m, pos
end

local function eval_boundary(a, input, start, raw, gmr, source, env, indent, fail_output_only, step)
   write_step(indent, step, "BOUNDARY")
   local pos = compile.boundary:match(input, start)
   local m = pos 				    -- set m to non-nil if pos is non-nil
   eval_report(m, pos, "token boundary", input, start, indent, fail_output_only, step)
   return m, pos
end

local function eval_sequence(a, input, start, raw, gmr, source, env, indent, fail_output_only, step)
   write_indent(indent)
   write("SEQUENCE: ", parse.reveal_ast(a), "\n")
   
   local pat = cinternals.compile_sequence(a, raw, gmr, source, env)
   local m, pos = compile.match_peg(Ct(pat.peg), input, start) 
   eval_report(m, pos, a, input, start, indent, fail_output_only, step)

   if not(m and fail_output_only) then
      write_indent(indent)
      write("Explanation:\n")

      local name, pos, text, subs, subidx = common.decode_match(a)
      -- sequences from the parser are always binary, i.e. there are exactly two subs.
      -- Regarding debugging... the failure of sub1 is fatal for a.
      local m, pos = eval_exp(subs[subidx], input, start, raw, gmr, source, env, indent+delta, fail_output_only, step)

      if not m then return nil; end		    -- Found the match error, so done.

      local name1, pos1, text1 = common.decode_match(subs[subidx])
      if not (raw or name1=="negation" or name1=="lookat") then
	 m, pos = eval_boundary(subs[subidx], input, pos, raw, gmr, source, env, indent+delta, fail_output_only, step)
      end
      if (not m) then
	 return nil;				    -- Found the match error, so done.
      else
	 return eval_exp(subs[subidx+1], input, pos, raw, gmr, source, env, indent+delta, fail_output_only, step)
      end
   end
   return m, pos
end

local function eval_choice(a, input, start, raw, gmr, source, env, indent, fail_output_only, step)
   write_indent(indent)
   write("CHOICE: ", parse.reveal_ast(a), "\n")
   
   local pat = cinternals.compile_choice(a, raw, gmr, source, env)
   local m, pos
   if raw then
      m, pos = compile.match_peg(Ct(pat.peg), input, start)
   else
      m, pos = compile.match_peg(Ct(pat.peg * compile.boundary), input, start)
   end
   eval_report(m, pos, a, input, start, indent, fail_output_only, step)

   if not(m and fail_output_only) then 
      write_indent(indent)
      write("Explanation:\n")

      -- The parser returns only binary choice tokens, i.e. there are exactly two subs.
      -- Regarding debugging...
      -- if sub1 and sub2 fail, then a fails.
      indent = indent + delta;
      local name, pos, text, subs, subidx = common.decode_match(a)
      local m, pos = eval_exp(subs[subidx], input, start, raw, gmr, source, env, indent,
			      fail_output_only, step)

      if m then
	 -- First alternative succeeded...
	 if raw then
	    -- ... and do NOT need to look for boundary
	    return m, pos;
	 else
	    local m2, pos2 =
	       eval_boundary(subs[subidx], input, pos, raw, gmr, source, env, indent, fail_output_only, step)
	    if (not m2) then
	       return nil;				    -- Found the match error, so done.
	    end
	 end -- if raw
      else
	 -- First alternative failed.  Trying second alternative:
	 write_indent(indent)
	 write("First option failed.  Proceeding to alternative.\n")
	 m, pos = eval_exp(subs[subidx+1], input, pos, raw, gmr, source, env, indent, fail_output_only, step)
	 if m then
	    -- Second alternative succeeded...
	    if raw then
	       -- ... and do NOT need to look for boundary
	       return m, pos;
	    else
	       local m2, pos2 =
		  eval_boundary(subs[subidx+1], input, pos, raw, gmr, source, env, indent+delta, fail_output_only, step)
	       if (not m2) then
		  return nil;			    -- Found the match error, so done.
	       end
	    end -- if raw
	 end -- if m (second alternative)
      end -- if m (first alternative)
   end
   return m, pos
end

local function eval_quantified_exp(a, input, start, raw, gmr, source, env, indent, fail_output_only, step)
   local epeg, qpeg, append_boundary, qname, min, max = cinternals.process_quantified_exp(a, raw, gmr, source, env)
   write_step(indent, step,
	      "QUANTIFIED EXP (",
	      (append_boundary and "tokenized/cooked): ") or "raw): ",
	      parse.reveal_ast(a))

   local m, pos = compile.match_peg(Ct(qpeg), input, start) 
   eval_report(m, pos, a, input, start, indent, fail_output_only, step)

--   descend into quantified exp's structure here?
--   write_indent(indent+delta)
--   write("(EXPLANATION) BASE EXP: ", parse.reveal_ast(a[3]), "\n")
--   ...

   return m, pos
end

local function eval_string(a, input, start, raw, gmr, source, env, indent, fail_output_only, step)
   write_step(indent, step, "LITERAL STRING: ", parse.reveal_ast(a))
   local name, pos, text, subs, subidx = common.decode_match(a)
   local m, pos = compile.match_peg(Ct(compile.unescape_string(text)), input, start)
   eval_report(m, pos, a, input, start, indent, fail_output_only, step)
   return m, pos
end

local function eval_charset(a, input, start, raw, gmr, source, env, indent, fail_output_only, step)
   local name, pos, text, subs, subidx = common.decode_match(a)
   write_step(indent, step,
	      "CHARACTER SET: ",
	      parse.reveal_ast(a),
	      (name=="range" and " (a character range)") or (" (a set of " .. #subs .. " characters)"))
   local pat = cinternals.compile_charset(a, raw, gmr, source, env)
   local m, pos = compile.match_peg(Ct(pat.peg), input, start) 
   eval_report(m, pos, a, input, start, indent, fail_output_only, step)
   return m, pos
end

local function eval_named_charset(a, input, start, raw, gmr, source, env, indent, fail_output_only, step)
   write_step(indent, step, "NAMED CHARSET: ", parse.reveal_ast(a))
   local pat = cinternals.compile_named_charset(a, raw, gmr, source, env)
   local m, pos = compile.match_peg(C(pat.peg), input, start)
   eval_report(m, pos, a, input, start, indent, fail_output_only, step)
   return m, pos
end

local function eval_negation(a, input, start, raw, gmr, source, env, indent, fail_output_only, step)
   write_step(indent, step, "NEGATION (NEGATIVE LOOK-AHEAD): ", parse.reveal_ast(a))
   
   local pat = cinternals.compile_negation(a, raw, gmr, source, env)
   local m, pos = compile.match_peg(C(pat.peg), input, start)
   eval_report(m, pos, a, input, start, indent, fail_output_only, step)

   if not(m and fail_output_only) then
      -- descend into negated exp
      local name, pos, text, subs, subidx = common.decode_match(a)
      write_indent(indent)
      write("Explanation: NEGATED EXPRESSION: ", parse.reveal_ast(subs[subidx]), "\n")
      local dm, dpos = eval_exp(subs[subidx], input, start, raw, gmr, source, env, indent+delta,
   fail_output_only, step)
   end
      -- We return the start position to indicate that the negation exp did not consume any
      -- input. 
   return m, start
end

local function eval_lookat(a, input, start, raw, gmr, source, env, indent, fail_output_only, step)
   write_indent(indent)
   write("LOOKAT (LOOK-AHEAD): ", parse.reveal_ast(a), "\n")
   
   local pat = cinternals.compile_lookat(a, raw, gmr, source, env)
   local m, pos = compile.match_peg(C(pat.peg), input, start)
   eval_report(m, pos, a, input, start, indent, fail_output_only, step)
   
   if not(m and fail_output_only) then
      -- descend into negated exp
      local name, pos, text, subs, subidx = common.decode_match(a)
      write_indent(indent)
      write("Explanation: LOOKAT EXPRESSION: ", parse.reveal_ast(subs[subidx]), "\n")
      local dm, dpos = eval_exp(subs[subidx], input, start, raw, gmr, source, env, indent+delta,
				fail_output_only, step)
   end
   -- We return the start position to indicate that the lookat exp did not consume any
   -- input. 
   return m, start
end

local function eval_grammar(a, input, start, raw, gmr, source, env, indent, fail_output_only, step)
   write_step(indent, step, "GRAMMAR:")
   write_indent(indent)
   write(reveal_ast_indented(a, indent), "\n")
   local name, pat = cinternals.compile_grammar_rhs(a, raw, gmr, source, env)
   local m, pos = compile.match_peg(Ct(pat.peg), input, start)
   eval_report(m, pos, a, input, start, indent, fail_output_only, step)
   -- How to descend into the definition of a grammar?
   return m, pos
end

eval_exp = function(ast, input, start, raw, gmr, source, env, indent, fail_output_only, step)
      local functions = {"eval_exp";
                      raw=eval_group;
                      cooked=eval_group;
                      choice=eval_choice;
                      sequence=eval_sequence;
                      negation=eval_negation;
                      lookat=eval_lookat;
		      identifier=eval_identifier;
                      string=eval_string;
                      named_charset=eval_named_charset;
                      charset=eval_charset;
                      quantified_exp=eval_quantified_exp;
		      grammar_=eval_grammar;
		   }
   return common.walk_ast(ast, functions, input, start, raw, gmr, source, env, indent,
      fail_output_only, step)
end

function eval.eval(source, input, start, env, fail_output_only)
   -- if fail_output_only is true, then we are using "eval" to explain a syntax error, not to dump
   -- a full trace of the entire matching process
   assert(type(source)=="string" and type(input)=="string" and (not env or type(env)=="table"))
   start = start or 1
   local indent = 5				  -- need to leave room for the step number "%3d."
   local raw = false;
   local step = {1};

   local pat = compile.compile_command_line_expression(source, env, raw)
   if not pat then return nil; end		    -- errors were already explained
   return eval_exp(pat.ast, input, start, raw, gmr, source, env, indent, fail_output_only, step)
end

return eval
