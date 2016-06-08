---- -*- Mode: Lua; -*-                                                                           
----
---- compile.lua   Compile Rosie Pattern Language to LPEG
----
---- © Copyright IBM Corporation 2016.
---- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
---- AUTHOR: Jamie A. Jennings


-- TO DO:
-- Clean up the loading of parse_and_explain (right now via rpl-parse)
-- And general cleanup, after so much evolution in the language definition!


local compile = {}				    -- exported top level interface
local cinternals = {}				    -- exported interface to compiler internals

-- forward reference
parse_and_explain = function(...)
		       error("Self-hosted parser not loaded")
		    end

local common = require "common"
local parse = require "parse"			    -- RPL parser and AST functions
local lpeg = require "lpeg"
require "utils"
require "recordtype"
local unspecified = recordtype.unspecified
syntax = require "syntax"

local P, V, C, S, R, Ct, Cg, Cp, Cc, Cmt, B =
   lpeg.P, lpeg.V, lpeg.C, lpeg.S, lpeg.R, lpeg.Ct, lpeg.Cg, lpeg.Cp, lpeg.Cc, lpeg.Cmt, lpeg.B

local locale = lpeg.locale()

----------------------------------------------------------------------------------------
-- Boundary for tokenization... this is going to be customizable, but hard-coded for now
----------------------------------------------------------------------------------------

local b_id = common.boundary_identifier

local boundary = locale.space^1 + #locale.punct
              + (lpeg.B(locale.punct) * #(-locale.punct))
	      + (lpeg.B(locale.space) * #(-locale.space))
	      + P(-1)
	      + (- B(1))
compile.boundary = boundary

----------------------------------------------------------------------------------------
-- Base environment, which can be extended with new_env, but not written to directly,
-- because it is shared between match engines.
----------------------------------------------------------------------------------------
local ENV = {["."] = pattern{name="."; peg=P(1); alias=true; raw=true};  -- any single character
             ["$"] = pattern{name="$"; peg=P(-1); alias=true; raw=true}; -- end of input
             [b_id] = pattern{name=b_id; peg=boundary; alias=true; raw=true}; -- token boundary
       }
setmetatable(ENV, {__tostring = function(env)
				   return "<base environment>"
				end;
		   __newindex = function(env, key, value)
				   error('Compiler: base environment is read-only, '
					 .. 'cannot assign "' .. key .. '"')
				end;
		})

cinternals.ENV = ENV

function compile.new_env(base_env)
   local env = {}
   base_env = base_env or ENV
   setmetatable(env, {__index = base_env;
		      __tostring = function(env)
				      return "<environment>"
				   end;})
   return env
end

function compile.flatten_env(env, output_table)
   output_table = output_table or {}
   local kind, color
   for item, value in pairs(env) do
      if not output_table[item] then
	 kind = (value.alias and "alias") or "definition"
	 if colormap then color = colormap[item] or ""; else color = ""; end;
	 output_table[item] = {type=kind, color=color}
      end
   end
   local mt = getmetatable(env)
   if mt and mt.__index then
      -- there is a parent environment
      return compile.flatten_env(mt.__index, output_table)
   else
      return output_table
   end
end

-- use this print function to see the nested environments
function compile.print_env_internal(env, skip_header, total)
   -- build a list of patterns that we can sort by name
   local pattern_list = {}
   local n = next(env)
   while n do
      table.insert(pattern_list, n)
      n = next(env, n);
   end
   table.sort(pattern_list)
   local patterns_loaded = #pattern_list
   total = (total or 0) + patterns_loaded

   local fmt = "%-30s %-15s %-8s"

   if not skip_header then
      print();
      print(string.format(fmt, "Pattern", "Kind", "Color"))
      print("------------------------------ --------------- --------")
   end

   local kind, color;
   for _,v in ipairs(pattern_list) do 
      local kind = (v.alias and "alias") or "definition";
      if colormap then color = colormap[v] or ""; else color = ""; end;
      print(string.format(fmt, v, kind, color))
   end

   if patterns_loaded==0 then
      print("<empty>");
   end
   local mt = getmetatable(env)
   if mt and mt.__index then
      print("\n----------- Parent environment: -----------\n")
      compile.print_env_internal(mt.__index, true, total)
   else
      print()
      print(total .. " patterns loaded")
   end
end

----------------------------------------------------------------------------------------
-- Syntax errors
----------------------------------------------------------------------------------------

function compile.explain_syntax_error(a, source)
   local errast = parse.syntax_error_check(a)
   assert(errast)
   local name, pos, text, subs = common.decode_match(a)
   local line, pos, lnum = extract_source_line_from_pos(source, pos)

   local msg = string.format("Syntax error at line %d: %s\n", lnum, text) .. string.format("%s\n", line)

   local err = parse.syntax_error_check(a)
   local ename, errpos, etext, esubs = common.decode_match(err)
   msg = msg .. (string.rep(" ", errpos-1).."^".."\n")

   if esubs then
      -- We only examine the first sub for now, assuming there are no others.  Must fix this
      -- later, although a new syntax error reporting technique is on the TO-DO LIST.
      local etname, etpos, ettext, etsubs = common.decode_match(esubs[1])
      if etname=="statement_prefix" then
	 msg = msg .. "Found start of a new statement inside an expression.\n"
      else
	 msg = msg .. "No additional information is available.\n"
      end
   end -- if esubs
   return msg
end

----------------------------------------------------------------------------------------
-- Compile-time errors
----------------------------------------------------------------------------------------

local function explain_quantified_limitation(a, source, maybe_rule)
   assert(a, "did not get ast in explain_quantified_limitation")
   local name, errpos, text = common.decode_match(a)
   local line, pos, lnum = extract_source_line_from_pos(source, errpos)
   local rule_explanation = (maybe_rule and "in pattern "..maybe_rule.." of:") or ""
   local msg = "Compile error: pattern with quantifier can match the empty string: " ..
      rule_explanation .. "\n" .. parse.reveal_ast(a) .. "\n" ..
      string.format("At line %d:\n", lnum) ..
      string.format("%s\n", line) ..
      string.rep(" ", pos) .. "^"
   coroutine.yield(false, msg)			    -- throw
end

local function explain_repetition_error(a, source)
   assert(a, "did not get ast in explain_repetition_error")
   local name, errpos, text = common.decode_match(a)
   local line, pos, lnum = extract_source_line_from_pos(source, errpos)

   local min = tonumber(rep_args[1]) or 0
   local max = tonumber(rep_args[2])

   local msg = "Compile error: integer quantifiers must be positive, and min <= max \n" ..
      "Error is in expression: " .. parse.reveal(a) .. "\n" ..
      string.format("At line %d:\n", lnum) ..
      string.format("%s\n", line) ..
      string.rep(" ", pos-1) .. "^"

   coroutine.yield(false, msg)			    -- throw
end

local function explain_undefined_identifier(a, source)
   assert(a, "did not get ast in explain_undefined_identifier")
   local name, errpos, text = common.decode_match(a)
   local line, pos, lnum = extract_source_line_from_pos(source, errpos)
   local msg = "Compile error: reference to undefined identifier " .. text .. "\n" ..
      string.format("At line %d:\n", lnum) ..
      string.format("%s\n", line) ..
      string.rep(" ", pos-1) .. "^"

   coroutine.yield(false, msg)				    -- throw
end

local function explain_undefined_charset(a, source)
   assert(a, "did not get ast in explain_undefined_charset")
   local _, errpos, name, subs = common.decode_match(a)
   local line, pos, lnum = extract_source_line_from_pos(source, errpos)
   local msg = "Compile error: named charset not defined " .. name .. "\n" ..
      string.format("At line %d:\n", lnum) ..
      string.format("%s\n", line) ..
      string.rep(" ", pos-1) .. "^"

   coroutine.yield(false, msg)				    -- throw
end

local function explain_unknown_quantifier(a, source)
   assert(a, "did not get ast in explain_unknown_quantifier")
   local name, errpos, text, subs = common.decode_match(a)
   local line, pos, lnum = extract_source_line_from_pos(source, errpos)
   local q = subs[2]				    -- IS THIS RIGHT?
   local msg = "Compile error: unknown quantifier " .. q .. "\n" ..
      string.format("At line %d:\n", lnum) ..
      string.format("%s\n", line) ..
      string.rep(" ", pos-1) .. "^"

   coroutine.yield(false, msg)				    -- throw
end


----------------------------------------------------------------------------------------
-- Compile
----------------------------------------------------------------------------------------

local function matches_empty(peg)
   local result = peg:match("")
   return result
end

-- THIS RATIONALE NO LONGER APPLIES DUE TO CHANGES IN THE BOUNDARY DEFINITION!
--
    -- Compiling quantified expressions is subtle when Rosie is tokenizing, i.e. in "cooked" mode.
    --    With a naive approach, this expression will always fail to recognize more than one word:
    --                    (","? word)*
    --    The reason is that the repetition ends up looking for the token boundary TWICE when the ","?
    --    fails.  And (in the absence of punctuation) since the token boundary consumes all whitespace
    --    (and must consume something), the second attempt to match boundary will fail because the
    --    prior attempt consumed all the whitespace.
--
-- INDEED, THE EXPRESSION (","? word)* WORKS GREAT!
-- 
    --    Here's the solution:
    --      Consider e*, e?, and e{0,m} where m>0.  Call these expressions qe.  When we
    --      have a sequence of qe followed by f, what we want to happen in cooked mode is
    --      this:
    --        match('qe f', "e f") -> match
    --        match('qe f', " f") -> no match, strictly speaking
    --        match('qe f', "f") -> match
    --      I.e. 'e* f' should work like '<e+ boundary f> / f'
    --           'e? f' should work like '<e boundary f> / f'
    --           'e{0,m} f' should work like '<e{1,m} boundary f> / f'
    --      And these can be rewritten as:
    --           '<e+ boundary f> / f'      -->  < <e+ boundary>? f >
    --           '<e boundary f> / f'       -->  < <e boundary>? f >
    --           '<e{1,m} boundary f> / f'  -->  < <e{1,m} boundary>? f >
    --      Conclusion: In cooked mode, quantified expressions like qe should compile as:
    --         e*     --> <e+ boundary>?
    --         e?     --> <e boundary>?
    --         e{0,m} --> <e{1,m} boundary>?
    --      Of course, the boundary is only necessary when qe appears in the context of a
    --      sequence, with terms coming after it.  Are there edge cases where it might be
    --      important to match qe without a boundary following it always?  Can't think of any (noting
    --      that the end of input is not an issue because boundary checks for that).
--
-- AND YES, THERE IS AN EDGE CASE IN WHICH WE WANT TO MATCH qe WITH NO BOUNDARY AFTER:
-- .match {("a")+ "b"}, "a ab"
-- THIS SHOULD PRODUCE A MATCH WHERE THE qe MATCHES "a a" AND THE {} glues it to "b".

function cinternals.process_quantified_exp(a, raw, gmr, source, env)
   assert(a, "did not get ast in process_quantified_exp")
   local name, pos, text, subs = common.decode_match(a)
   assert(name=="new_quantified_exp")
   -- Regarding debugging... the quantified exp a[1] fails as soon as:
   -- e^0 == e* can never fail, because it can match the empty string.
   -- e^1 == e+ fails when as soon as the initial attempt to match e fails.
   -- e^-1 == e? can never fail because it can match the empty string
   -- e{n,m} == (e * e ...)*e^(m-n) will fail when any of the sequence fails.

   -- if (((not raw) and subname~="raw" 
   --                and subname~="charset" 
   -- 		  and subname~="named_charset"
   -- 		  and subname~="string" 
   --                and subname~="identifier"
   --                and subname~="ref"
   -- 	    )
   --    or subname=="cooked") then
   --    append_boundary = true;
   -- end

   local qpeg, min, max
   local append_boundary = true
   local subname, subbody = next(subs[1])

   raw = (subname=="raw_exp")
   if raw then
      subname, subbody = next(subbody.subs[1])
      append_boundary = false
   end

   local e = cinternals.compile_exp(subs[1], raw, gmr, source, env)
   local epeg = e.peg

   if (not gmr) and matches_empty(epeg) then
      explain_quantified_limitation(a, source);
   end

   local q = subs[2]
   assert(q, "not getting quantifier clause in process_quantified_exp")
   local qname, qpos, qtext, qsubs = common.decode_match(q)
   if qname=="plus" then
      if append_boundary then qpeg=(epeg * boundary)^1
      else qpeg=epeg^1
      end
   elseif qname=="star" then
      if append_boundary then qpeg = (epeg * (boundary * epeg)^0)^-1
      else qpeg=epeg^0
      end
   elseif qname=="question" then
      qpeg = epeg^-1
   elseif qname=="repetition" then
      assert(type(qsubs[1])=="table")
      assert(qsubs[1], "not getting min clause in process_quantified_exp")
      local mname, mpos, mtext = common.decode_match(qsubs[1])
      assert(mname=="low")
      min = tonumber(mtext) or 0
      assert(qsubs[2], "not getting max clause in process_quantified_exp")
      local mname, mpos, mtext = common.decode_match(qsubs[2])
      max = tonumber(mtext)
      if (min < 0) or (max and (max < 0)) or (max and (max < min)) then
	 explain_repetition_error(a, source)
      end
      if (not max) then
	 if (min == 0) then
	    -- same as star
	    if append_boundary then qpeg = (epeg * (boundary * epeg)^0)^-1
	    else qpeg=epeg^0
	    end
	 else
	    -- min > 0 due to prior checking
	    assert(min > 0)
	    if append_boundary then qpeg = (epeg * (boundary * epeg)^(min-1))
	    else qpeg = epeg^min
	    end
	 end
      else
	 -- here's where things get interesting, because we must match at least min copies of
	 -- epeg, and at most max.
	 if min==0 then
	    qpeg = ((append_boundary and (boundary * epeg)) or epeg)^(-max)
	 else
	    assert(min > 0)
	    qpeg = epeg
	    for i=1,(min-1) do
	       qpeg = qpeg * ((append_boundary and (boundary * epeg)) or epeg)
	    end -- for
	    if (min-max) < 0 then
	       qpeg = qpeg * ((append_boundary and (boundary * epeg) or epeg)^(min-max))
	    else
	       assert(min==max)
	    end
	 end -- if min==0
      end
   else						    -- switch on quantifier type
      explain_unknown_quantifier(a, source)
   end
   -- return peg being quantified, quantified peg, whether boundary was appended, quantifier name, min, max
   return e.peg, qpeg, append_boundary, qname, min, max
end

function cinternals.compile_quantified_exp(a, raw, gmr, source, env)
   assert(a, "did not get ast in compile_quantified_exp")
   local epeg, qpeg, append_boundary, qname, min, max = cinternals.process_quantified_exp(a, raw, gmr, source, env)
   return pattern{name=qname, peg=qpeg};
end

function cinternals.compile_new_quantified_exp(a, raw, gmr, source, env)
   assert(a, "did not get ast in compile_cooked_quantified_exp")
   local epeg, qpeg, append_boundary, qname, min, max = cinternals.process_quantified_exp(a, true, gmr, source, env)
   return pattern{name=qname, peg=qpeg, ast=a};
end

function cinternals.compile_string(a, raw, gmr, source, env)
   assert(a, "did not get ast in compile_string")
   local name, pos, text = common.decode_match(a)
   local str = common.unescape_string(text)
   if (not raw) and (locale.space:match(str) or locale.space:match(str, -1)) then
      warn('Literal string begins or ends with whitespace, outside of raw mode: "'
	   .. text .. '"')
   end
   return pattern{name=name; peg=P(str)}
end

function cinternals.compile_identifier(a, raw, gmr, source, env)
   assert(a, "did not get ast in compile_identifier")
   local _, pos, name = common.decode_match(a)
   local val = env[name]
   if (not val) then explain_undefined_identifier(a, source); end -- throw
   assert(pattern.is(val), "Did not get a pattern: "..tostring(val))
   if val.alias then 
      return pattern{name=name, peg=val.peg, ast=val.ast}
   else
      return pattern{name=name,
		     peg=cinternals.wrap_peg(val, name, raw), 
		     ast=val.ast}
   end
end

function cinternals.compile_ref(a, raw, gmr, source, env)
   assert(a, "did not get ast in compile_ref")
   local reftype, pos, name = common.decode_match(a)
   local pat = env[name]
   if (not pat) then explain_undefined_identifier(a, source); end -- throw
   assert(pattern.is(pat), "Did not get a pattern: "..tostring(pat))
   return pattern{name=name, peg=pat.peg}
end

function cinternals.compile_predicate(a, raw, gmr, source, env)
   assert(a, "did not get ast in compile_predicate")
   local name, pos, text, subs = common.decode_match(a)
   local peg = cinternals.compile_exp(subs[2], raw, gmr, source, env).peg
   local pred_clause = subs[1]
   local pred_name = next(pred_clause)
   if pred_name=="negation" then peg = (- peg)
   elseif pred_name=="lookat" then peg = (# peg)
   else error("Internal compiler error: unknown predicate type: " .. tostring(pred_name))
   end
   return pattern{name=pred, peg=peg, ast=a}
end

function cinternals.compile_sequence(a, raw, gmr, source, env)
   assert(a, "did not get ast in compile_sequence")
   -- sequences from the parser are always binary, i.e. with 2 subs.
   -- Regarding debugging... the failure of subs[1] is fatal for a.
   local name, pos, text, subs = common.decode_match(a)
   local peg1, peg2
   peg1 = cinternals.compile_exp(subs[1], raw, gmr, source, env).peg
   peg2 = cinternals.compile_exp(subs[2], raw, gmr, source, env).peg
   if raw or (next(subs[1])=="predicate")
   then
      return pattern{name=name, peg=peg1 * peg2}
   else
--      print("************* adding a boundary to the PEG itself in compile_sequence **************")
      return pattern{name=name, peg=peg1 * boundary * peg2}
   end
end
   
function cinternals.compile_named_charset(a, raw, gmr, source, env)
   assert(a, "did not get ast in compile_named_charset")
   local name, pos, text = common.decode_match(a)
   local pat = locale[text]
   if not pat then
      explain_undefined_charset(a, source)
   end
   return pattern{name=name, peg=pat}
end

function cinternals.compile_charset(a, raw, gmr, source, env)
   assert(a, "did not get ast in compile_charset")
   local name, pos, text, subs = common.decode_match(a)
   if next(subs[1])=="range" then
      local r = subs[1]
      assert(r, "did not get range ast in compile_charset")
      local rname, rpos, rtext, rsubs = common.decode_match(r)
      assert(not rsubs[3])
      assert(next(rsubs[1])=="character")
      assert(next(rsubs[2])=="character")
      local cname1, cpos1, ctext1 = common.decode_match(rsubs[1])
      local cname2, cpos2, ctext2 = common.decode_match(rsubs[2])
      return pattern{name=name, peg=R(common.unescape_string(ctext1)..common.unescape_string(ctext2))}
   elseif next(subs[1])=="charlist" then
      local exps = "";
      assert(subs[1], "did not get charlist sub in compile_charset")
      local clname, clpos, cltext, clsubs = common.decode_match(subs[1])
      for i = 1, #clsubs do
	 local v = clsubs[i]
	 assert(next(v)=="character", "did not get character sub in compile_charset")
	 local cname, cpos, ctext = common.decode_match(v)
	 exps = exps .. common.unescape_string(ctext)
      end
      return pattern{name=name, peg=S(exps)}
   else
      error("Internal error (compiler): Unknown charset type: "..next(subs[1]))
   end
end

function cinternals.compile_choice(a, raw, gmr, source, env)
   assert(a, "did not get ast in compile_choice")
   -- Choice ASTs will have exactly two alternatives
   -- Regarding debugging... 'a' fails only if both alternatives fail
   local name, pos, text, subs = common.decode_match(a)
   local peg1 = cinternals.compile_exp(subs[1], raw, gmr, source, env).peg
   local peg2 = cinternals.compile_exp(subs[2], raw, gmr, source, env).peg
   return pattern{name=name,
		  peg=(peg1+peg2),
		  alternates = { C(peg1), C(peg2) }}
end

function cinternals.wrap_peg(pat, name, raw)
   local peg
   if pat.alternates and (not raw) then
      -- The presence of pat.alternates means this pattern came from a CHOICE exp, in which case 
      -- val.peg already holds the compiler result for this node.  But val.peg was calculated 
      -- assuming RAW mode.  So if we are NOT in raw mode, then we must finish the compilation in
      -- a special way.
      peg = ( common.match_node_wrap(pat.alternates[1], name) * boundary ) + ( common.match_node_wrap(pat.alternates[2], name) * boundary )
   else
      peg = common.match_node_wrap(pat.peg, name)
   end
   return peg
end

function cinternals.compile_group(a, raw, gmr, source, env)
   assert(a, "did not get ast in compile_group")
   local name, pos, text, subs = common.decode_match(a)
   assert(name=="raw" or name=="cooked" or name=="raw_exp")
   if (name=="raw") or (name=="raw_exp") then raw=true; else raw=false; end
   assert(not subs[2])
   local pat = cinternals.compile_exp(subs[1], raw, gmr, source, env)
   return pattern{name=name, peg=pat.peg, ast=pat.ast, alternates=pat.alternates}
end

function cinternals.compile_syntax_error(a, raw, gmr, source, env)
   assert(a, "did not get ast in compile_syntax_error")
   error("Compiler called on source code with errors! " .. parse.reveal_exp(a))
end

function cinternals.compile_grammar_rhs(a, raw, gmr, source, env)
   assert(a, "did not get ast in compile_grammar")
   local name, pos, text, subs = common.decode_match(a)
   assert(name=="grammar_" or name=="new_grammar")
   assert(type(subs[1])=="table")
   assert(type(source)=="string")
   local gtable = compile.new_env(env)
   local first = subs[1]			    -- first rule in grammar
   assert(first, "not getting first rule in compile_grammar")
   local fname, fpos, ftext = common.decode_match(first)
   assert(first and (fname=="assignment_" or fname=="alias_" or fname=="binding"))

   local rule, id_node, id, exp_node
   
   -- first pass: collect rule names as V() refs into a new env
   for i = 1, #subs do			    -- for each rule
      local rule = subs[i]
      assert(rule, "not getting rule in compile_grammar")
      local rname, rpos, rtext, rsubs = common.decode_match(rule)
      local id_node = rsubs[1]			    -- identifier clause
      assert(id_node and next(id_node)=="identifier")
      local iname, ipos, id = common.decode_match(id_node)
      gtable[id] = pattern{name=id, peg=V(id), alias=(rname=="alias_")}
   end						    -- for

   -- second pass: compile right hand sides in gtable environment
   local pats = {}
   local start
   for i = 1, #subs do			    -- for each rule
      rule = subs[i]
      assert(rule, "not getting rule in compile_grammar")
      local rname, rpos, rtext, rsubs = common.decode_match(rule)
      id_node = rsubs[1]			    -- identifier clause
      assert(id_node, "not getting id_node in compile_grammar")
      local iname, ipos, id, isubs = common.decode_match(id_node)
      if not start then start=id; end		    -- first rule is start rule
      exp_node = rsubs[2]			    -- expression clause
      assert(exp_node, "not getting exp_node in compile_grammar")
      -- flags: not raw, inside grammar
      pats[id] = cinternals.compile_exp(exp_node, false, true, source, gtable)
      if (fname=="binding" and not syntax.contains_capture(exp_node)) then
	 gtable[id].alias=true;
      end
   end						    -- for

   -- third pass: create the table that will create the LPEG grammar by stripping off the Rosie
   -- pattern records, and wrapping as needed with lpeg.C
   local t = {}
   for id, pat in pairs(pats) do		    -- for each rule
      if gtable[id].alias then
	    t[id] = pat.peg			    -- the old grammar way
      else
	 if (name=="new_grammar") then
	    --t[id] = common.match_node_wrap(C(pat.peg), id)
	    t[id]=pat.peg
	 else
	    t[id] = C(pat.peg)			    -- the old grammar way
	 end
      end
   end						    -- for
   t[1] = start					    -- first rule is start rule
   local success, peg_or_msg = pcall(P, t)	    -- P(t) while catching errors
   if success then
      return start, pattern{name="grammar", peg=peg_or_msg, ast=a, alias=gtable[t[1]].alias}
   else -- failed
      local rule = peg_or_msg:match("'%w'$")
      table.print(a)				    -- !@#
      print(peg_or_msg)				    -- !@#
      -- !@# FIXME:
      -- Explain some error that may not be related to quantifier!  Change the call below: 
      explain_quantified_limitation(a, source, rule)
   end
end

function cinternals.compile_grammar(a, raw, gmr, source, env)
   local name, pat = cinternals.compile_grammar_rhs(a, raw, gmr, source, env)
   -- if no pattern returned, then errors were already explained
   if pat then
      if env[name] and not QUIET then
	 warn("Compiler: reassignment to identifier " .. name)
      end
--      if next(a)=="new_grammar" then
	 --print("=================================================== Compiling new_grammar: " .. name)
	 -- pat.peg = common.match_node_wrap(C(pat.peg), name)
--      end
      env[name] = pat
   end
end

function cinternals.compile_capture(a, raw, gmr, source, env)
   assert(a, "did not get ast in compile_capture")
--   print("compile_capture: " .. parse.reveal_ast(a) .. " and raw is " .. tostring(raw))
   local name, pos, text, subs = common.decode_match(a)
   assert(name=="capture")
   assert(subs and subs[1] and subs[2] and (not subs[3]), "wrong number of subs in capture ast")
   local ref_exp, captured_exp = subs[1], subs[2]
   local cap_name, cap_pos, cap_text, cap_subs = common.decode_match(captured_exp)
   local pat

   assert(compile.expression_p(captured_exp),
	  "compile_capture called with an ast that is not an expression: " .. (next(captured_exp)))

   local refname, _, reftext, _ = common.decode_match(ref_exp)
   assert(refname=="ref")
   assert(type(reftext)=="string")

   -- if cap_name=="choice" then
   --    local choices = syntax.flatten_choice(captured_exp)
   --    choices = map(function(c)
   -- 		       local pat = cinternals.compile_exp(c, raw, gmr, source, env)
   -- 		       return common.match_node_wrap(pat.peg, reftext)
   -- 		    end,
   -- 		    choices)
   --    local final_peg = reduce(function(p1, p2) return p1 + p2; end,
   -- 			       car(choices),
   -- 			       cdr(choices))
   --    pat = pattern{name=cap_name, peg=final_peg}
   -- else
      pat = cinternals.compile_exp(captured_exp, raw, gmr, source, env)
--   end

   pat.name = cap_name
   pat.peg = common.match_node_wrap(C(pat.peg), reftext)
   return pat
end

cinternals.compile_exp_functions = {"compile_exp";
				    capture=cinternals.compile_capture;	    
				    ref=cinternals.compile_ref;
				    predicate=cinternals.compile_predicate;
				    raw_exp=cinternals.compile_group;
				    --raw=cinternals.compile_group;
				    --cooked=cinternals.compile_group;
				    choice=cinternals.compile_choice;
				    sequence=cinternals.compile_sequence;
				    --identifier=cinternals.compile_identifier;
				    string=cinternals.compile_string;
				    named_charset=cinternals.compile_named_charset;
				    charset=cinternals.compile_charset;
				    --quantified_exp=cinternals.compile_quantified_exp;
				    new_quantified_exp=cinternals.compile_new_quantified_exp;
				    syntax_error=cinternals.compile_syntax_error;
				 }

function cinternals.compile_exp(a, raw, gmr, source, env)
   return common.walk_ast(a, cinternals.compile_exp_functions, raw, gmr, source, env)
end

function compile.expression_p(ast)
   local name, pos, text, subs = common.decode_match(ast)
   return not (not cinternals.compile_exp_functions[name])
end

function cinternals.cook_if_needed(a)
   local name = common.decode_match(a)
   if name~="raw" and name~="cooked" then
      return common.create_match("cooked", 1, "(...)", a)
   else
      return a
   end
end

local boundary_ast = common.create_match("ref", 0, common.boundary_identifier)
local looking_at_boundary_ast = common.create_match("predicate",
						    0,
						    "@/generated/",
						    common.create_match("lookat", 0, "@/generated/"),
						    boundary_ast)

function cinternals.append_boundary(a)
   return common.create_match("sequence", 1, "/generated/", a, looking_at_boundary_ast)
end

function cinternals.compile_assignment(a, raw, gmr, source, env)
   assert(a, "did not get ast in compile_assignment")
   local name, pos, text, subs = common.decode_match(a)
   assert(name=="assignment_" or name=="alias_")
   assert(next(subs[1])=="identifier")
   assert(type(subs[2])=="table")			    -- the right side of the assignment
   assert(not subs[3])
   assert(type(source)=="string")
   local _, ipos, iname = common.decode_match(subs[1])
   if env[iname] and not QUIET then
      warn("Compiler: reassignment to identifier " .. iname)
   end

  local rhs = cinternals.cook_if_needed(subs[2])
--  local rhs = syntax.cook_if_needed(subs[2])
--   local rhs = syntax.cooked_to_raw(syntax.cook_if_needed(subs[2]))

   local pat = cinternals.compile_exp(rhs, raw, gmr, source, env)
   -- N.B. If the RHS of the expression is a CHOICE node, and this is NOT AN ALIAS then the value
   -- we compute here for pat.peg is only valid when the identifier being bound is later
   -- referenced in RAW mode.  If the identifier is referenced in COOKED mode, then we must ignore
   -- pat.peg and use the pat.alternates value to compute the correct peg.  That computation must
   -- be done in conjunction with match_node_wrap.
   if name=="alias_" then
      pat.alias=true
   else
      pat.peg = C(pat.peg)
   end
   pat.ast = rhs;
   env[iname] = pat
end

function cinternals.compile_binding(a, raw, gmr, source, env)
   assert(a, "did not get ast in compile_binding")
   local name, pos, text, subs = common.decode_match(a)
   local lhs, rhs = subs[1], subs[2]
   assert(next(lhs)=="identifier")
   assert(type(rhs)=="table")			    -- the right side of the assignment
   assert(not subs[3])
   assert(type(source)=="string")
   local _, ipos, iname = common.decode_match(lhs)
   if env[iname] and not QUIET then
      warn("Compiler: reassignment to identifier " .. iname)
   end

   local pat = cinternals.compile_rhs(rhs, raw, gmr, source, env, iname)
   env[iname] = pat
   return pat
end

function cinternals.compile_rhs(a, raw, gmr, source, env, iname)
   assert(type(a)=="table", "did not get ast in compile_rhs: " .. tostring(a))
   if not compile.expression_p(a) then
      local msg = string.format('Compile error: expected an expression, but received %q',
				parse.reveal_ast(a))
      error(msg)
   end
   local rhs_name, rhs_body = next(a)
   local raw_exp = (rhs_name=="raw_exp")
   local pat = cinternals.compile_exp(a, true, gmr, source, env)
   pat.raw = (rhs_name=="raw_exp")
   if syntax.contains_capture(a) then
      assert(((rhs_name=="capture") or
	      (rhs_name=="raw_exp" and next(rhs_body.subs[1])=="capture")), 
	     "Compiling binding for ASSIGNMENT " .. iname .. " but rhs not a capture")
      pat.alias=false
   else
      pat.alias=true
   end
   pat.ast = a;
   return pat
end

function cinternals.compile_ast(ast, raw, gmr, source, env)
   assert(type(ast)=="table", "Compiler: first argument not an ast: "..tostring(ast))
   local functions = {"compile_ast";
		      --assignment_=cinternals.compile_assignment;
		      --alias_=cinternals.compile_assignment;
		      binding=cinternals.compile_binding;
		      --grammar_=cinternals.compile_grammar;
		      new_grammar=cinternals.compile_grammar;
		      exp=cinternals.compile_exp;
		      default=cinternals.compile_exp;
		   }
   return common.walk_ast(ast, functions, raw, gmr, source, env)
end

function cinternals.compile_astlist(astlist, raw, gmr, source, env)
   assert(type(astlist)=="table", "Compiler: first argument not a list of ast's: "..tostring(a))
   assert(type(source)=="string")
   local results = {}
   local run_compiler = function(ast) return cinternals.compile_ast(ast, raw, gmr, source, env); end
   return map(run_compiler, astlist)
end

----------------------------------------------------------------------------------------
-- Top-level interface to compiler
----------------------------------------------------------------------------------------

compile.parser = parse.core_parse_and_explain;	    -- note: parser is a dynamic variable

function compile.compile(source, env)
   local astlist, original_astlist = compile.parser(source)
   if not astlist then return false, original_astlist; end -- original_astlist is msg
   assert(type(astlist)=="table")
   assert(type(original_astlist)=="table")
   assert(type(env)=="table", "Compiler: environment argument is not a table: "..tostring(env))
   local c = coroutine.create(cinternals.compile_astlist)
   local no_lua_error, results, msg = coroutine.resume(c, astlist, false, false, source, env)
   if no_lua_error then
      if results then
      	 foreach(function(pat, oast) pat.original_ast=oast; end, results, original_astlist)
      end
      return results, msg			    -- msg may contain compiler warnings
   else
      error("Internal error (compiler): " .. tostring(results) .. " / " .. tostring(msg))
   end
end

-- was compile_command_line_expression
function compile.compile_match_expression(source, env)
   assert(type(env)=="table", "Compiler: environment argument is not a table: "..tostring(env))

   local astlist, original_astlist = compile.parser(source)
   if (not astlist) then
      return false, original_astlist		    -- original_astlist is msg
   end
   assert(type(astlist)=="table")
   assert(type(original_astlist)=="table")

   -- After adding support for semi-colons to end statements, can change this restriction to allow
   -- arbitrary statements, followed by an expression, like scheme's 'begin' form.
   if (#astlist~=1) then
      local msg = "Error: source did not compile to a single pattern: " .. source
      for i, a in ipairs(astlist) do
	 msg = msg .. "\nPattern " .. i .. ": " .. parse.reveal_ast(a)
      end
      return false, msg
   elseif not compile.expression_p(astlist[1]) then
      -- Statements won't produce a pattern
      local msg = "Error: only expressions can be matched (not statements): " .. source
      return false, msg
   end

   local ast = astlist[1]
   local orig_ast = original_astlist[1]
   local name, pos, text, subs = common.decode_match(ast)
   local pat, raw_expression_flag

   if (name=="ref") or (name=="identifier") then
      pat = env[text]
      raw_expression_flag = (((name=="ref") and pattern.is(pat) and pat.raw)
			     or
			      -- else name=="identifier"
			     (pattern.is(pat) and pat.ast and (next(pat.ast)=="raw_exp")) or
		             (pattern.is(pat) and (not pat.ast) and pat.raw))
      if (not raw_expression_flag) then
	 ast = syntax.append_looking_at_boundary(ast)
      end
   end

   local c = coroutine.create(cinternals.compile_exp)
   local no_lua_error, result, msg = coroutine.resume(c, ast, false, false, source, env)
   if (not no_lua_error) then
      error("Internal error (compiler): " .. tostring(result) .. " / " .. tostring(msg))
   end

   -- one ast will compile to one pattern
   if not (result and pattern.is(result)) then
      return false, msg
   end

   result.ast = ast
   result.original_ast = orig_ast

   -- if the expression was a ref (i.e. an identifier), then it does not have to be anonymous

   if not (pat and (not pat.alias)) then
      -- if the user entered an identifier, then we are all set, unless it is an alias, which
      -- by itself may capture nothing and thus should be handled like any other kind of
      -- expression.  
      -- BUT if the user entered an expression other than an identifier, we should treat it like it
      -- is the RHS of an assignment statement.  need to give it a name, so we label it "*"
      -- since that can't be an identifier name 
--print("*** WRAPPING NON-IDENTIFIER ENTERED AT TOP LEVEL: " .. parse.reveal_ast(ast) .. " ***")
      result.peg = common.match_node_wrap(C(result.peg), "*")

   else
      -- Top-level wrap to turn this into a matchable expression
--      result.peg = (result.peg * Cp())		    -- !@# is this needed?
   end
   return result
end
   
function compile.compile_file(filename, env)
   local f = io.open(filename);
   if (not f) then
      return false, 'Compiler: cannot open file "'..filename..'"'
   end
   local source = f:read("a")
   f:close()
   if type(source)~="string" then
      return false, 'Compiler: unreadable file "'..filename..'"'
   end
   return compile.compile(source, env)
end

function compile.compile_core(filename, env)
   local source
   local f = io.open(filename);
   if (not f) then
      return false, 'Compiler: cannot open file of core definitions "'..filename..'"\nExiting...\n'
   else
      source = f:read("a")
      f:close()
   end
   assert(type(env)=="table", "Compiler: environment argument is not a table: "..tostring(env))
   -- intentionally ignoring the value of compile.parse, we ensure the use of
   -- core_parse_and_explain for parsing the Rosie rpl
   local astlist = parse.core_parse_and_explain(source)
   if not astlist then return nil; end		    -- errors have been explained already
   cinternals.compile_astlist(astlist, false, false, source, env)
   return true
end

----------------------------------------------------------------------------------------
-- Low level match functions (user level functions use engines)
----------------------------------------------------------------------------------------

function compile.match_peg(peg, input, start)
   return (peg * Cp()):match(input, start)
end


compile.cinternals = cinternals
return compile
