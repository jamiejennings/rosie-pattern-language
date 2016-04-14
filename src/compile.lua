---- -*- Mode: Lua; -*-                                                                           
----
---- compile.lua   Compile Rosie Pattern Language to LPEG
----
---- © Copyright IBM Corporation 2016.
---- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
---- AUTHOR: Jamie A. Jennings


-- TO DO:
-- Clean up the loading of parse_and_explain (right now via rpl-parse)

-- 

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

local P, V, C, S, R, Ct, Cg, Cp, Cc, Cmt =
   lpeg.P, lpeg.V, lpeg.C, lpeg.S, lpeg.R, lpeg.Ct, lpeg.Cg, lpeg.Cp, lpeg.Cc, lpeg.Cmt

local locale = lpeg.locale()

----------------------------------------------------------------------------------------
-- Base environment, which can be extended with new_env, but not written to directly,
-- because it is shared between match engines.
----------------------------------------------------------------------------------------
local ENV = {["."] = pattern{name="."; peg=P(1); alias=true};	-- any single character
       ["$"] = pattern{name="$"; peg=P(-1); alias=true}; -- end of input
       }
setmetatable(ENV, {__tostring = function(env)
				   return "<base environment>"
				end;
		   __newindex = function(env, key, value)
				   error('Compiler: base environment is read-only, '
					 .. 'cannot assign "' .. key .. '"')
				end;
		})

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
   local name, pos, text, subs, subidx = common.decode_match(a)
   local line, pos, lnum = extract_source_line_from_pos(source, pos)

   local msg = string.format("Syntax error at line %d: %s\n", lnum, text) .. string.format("%s\n", line)

   local err = parse.syntax_error_check(a)
   local ename, errpos, etext, esubs, esubidx = common.decode_match(err)
   msg = msg .. (string.rep(" ", errpos-1).."^".."\n")

   if esubs then
      -- We only examine the first sub, assuming there are no others.  Is that right?
      local etname, etpos, ettext, etsubs, etsubidx = common.decode_match(esubs[esubidx])
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

local magic_string = "This is Rosie!";

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
--   error(magic_string)				    -- throw

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
   local _, errpos, name, subs, subidx = common.decode_match(a)
   local line, pos, lnum = extract_source_line_from_pos(source, errpos)
   local msg = "Compile error: named charset not defined " .. name .. "\n" ..
      string.format("At line %d:\n", lnum) ..
      string.format("%s\n", line) ..
      string.rep(" ", pos-1) .. "^"

   coroutine.yield(false, msg)				    -- throw
end

local function explain_unknown_quantifier(a, source)
   assert(a, "did not get ast in explain_unknown_quantifier")
   local name, errpos, text, subs, subidx = common.decode_match(a)
   local line, pos, lnum = extract_source_line_from_pos(source, errpos)
   local q = subs[subidx+1]			    -- IS THIS RIGHT?
   local msg = "Compile error: unknown quantifier " .. q .. "\n" ..
      string.format("At line %d:\n", lnum) ..
      string.format("%s\n", line) ..
      string.rep(" ", pos-1) .. "^"

   coroutine.yield(false, msg)				    -- throw
end


----------------------------------------------------------------------------------------
-- Compile
----------------------------------------------------------------------------------------

local boundary = locale.space^1 + #locale.punct
              + (lpeg.B(locale.punct) * #(-locale.punct))
	      + (lpeg.B(locale.space) * #(-locale.space))
	      + P(-1)
compile.boundary = boundary

local function matches_empty(peg)
   local result = peg:match("")
   return result
end

-- Compiling quantified expressions is subtle when Rosie is tokenizing, i.e. in "cooked" mode.
--    With a naive approach, this expression will always fail to recognize more than one word:
--                    (","? word)*
--    The reason is that the repetition ends up looking for the token boundary TWICE when the ","?
--    fails.  And (in the absence of punctuation) since the token boundary consumes all whitespace
--    (and must consume something), the second attempt to match boundary will fail because the
--    prior attempt consumed all the whitespace.
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

function cinternals.process_quantified_exp(a, raw, gmr, source, env)
   assert(a, "did not get ast in process_quantified_exp")
   local name, pos, text, subs, subidx = common.decode_match(a)
   assert(name=="quantified_exp")
   -- Regarding debugging... the quantified exp a[1] fails as soon as:
   -- e^0 == e* can never fail, because it can match the empty string.
   -- e^1 == e+ fails when as soon as the initial attempt to match e fails.
   -- e^-1 == e? can never fail because it can match the empty string
   -- e{n,m} == (e * e ...)*e^(m-n) will fail when any of the sequence fails.
   local qpeg, min, max
   local e = cinternals.compile_exp(subs[subidx], raw, gmr, source, env)
   local epeg = e.peg
   local append_boundary = false
   if (((not raw) and next(subs[subidx])~="raw" 
                  and next(subs[subidx])~="charset" 
		  and next(subs[subidx])~="named_charset"
		  and next(subs[subidx])~="string" 
		  and next(subs[subidx])~="identifier"
	    )
      or next(subs[subidx])=="cooked") then
      append_boundary = true;
   end

   if (not gmr) and matches_empty(epeg) then
      explain_quantified_limitation(a, source);
   end

   local q = subs[subidx+1]
   assert(q, "not getting quantifier clause in process_quantified_exp")
   local qname, qpos, qtext, qsubs, qsubidx = common.decode_match(q)
   if qname=="plus" then
      if append_boundary then qpeg=(epeg * boundary)^1
      else qpeg=epeg^1
      end
   elseif qname=="star" then
      if append_boundary then qpeg = ((epeg * boundary)^1)^-1 -- yep.
      else qpeg=epeg^0
      end
   elseif qname=="question" then
      if append_boundary then qpeg = (epeg * boundary)^-1
      else qpeg=epeg^-1
      end
   elseif qname=="repetition" then
      assert(type(qsubs[qsubidx])=="table")
      assert(qsubs[qsubidx], "not getting min clause in process_quantified_exp")
      local mname, mpos, mtext = common.decode_match(qsubs[qsubidx])
      assert(mname=="low")
      min = tonumber(mtext) or 0
      assert(qsubs[qsubidx+1], "not getting max clause in process_quantified_exp")
      local mname, mpos, mtext = common.decode_match(qsubs[qsubidx+1])
      max = tonumber(mtext)
      if (min < 0) or (max and (max < 0)) or (max and (max < min)) then
	 explain_repetition_error(a, source)
      end
      if (not max) then
	 if (min == 0) then
	    -- same as star
	    if append_boundary then qpeg = ((epeg * boundary)^1)^-1
	    else qpeg = epeg^0
	    end
	 else
	    -- min > 0 due to prior checking
	    assert(min > 0)
	    if append_boundary then qpeg = (epeg * boundary)^min
	    else qpeg = epeg^min
	    end
	 end
      else
	 -- here's where things get interesting, because we must see at least min copies of epeg,
	 -- and at most max.
	 qpeg=P"";
	 for i=1,min do
	    qpeg = qpeg * ((append_boundary and (epeg * boundary)) or epeg)
	 end -- for
	 if (min-max) < 0 then
	    qpeg = qpeg * ((append_boundary and (epeg * boundary) or epeg)^(min-max))
	 else
	    assert(min==max)
	 end
	 -- finally, here's the check for "and not looking at another copy of epeg"
	 qpeg = qpeg * (-epeg)
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
   --   local enumerate = function(input, pos, ...)      -- TESTING!
   --                        return pos, ...
   --                     end

   local val = env[name]
   if (not val) then
      explain_undefined_identifier(a, source);
   end
   assert(pattern.is(val), "Did not get a pattern: "..tostring(val))
   if val.alias then 
      return pattern{name=name, peg=val.peg, ast=val.ast}
   else

      -- TESTING!
      --      if name=="process" then
      --	 return pattern{name=name, peg=Cmt(Ct(Cg(Ct(val.peg), name)), enumerate), ast=val.ast}
      --      else
      --
      --	 return pattern{name=name, peg=Ct(Cg(Ct(val.peg), name)), ast=val.ast}

      return pattern{name=name,
		     peg=cinternals.wrap_peg(val, name, raw), 
		     ast=val.ast}
   
      --      end
   end
end
      
function cinternals.compile_negation(a, raw, gmr, source, env)
   assert(a, "did not get ast in compile_negation")
   local name, pos, text, subs, subidx = common.decode_match(a)
   local peg = cinternals.compile_exp(subs[subidx], raw, gmr, source, env).peg
   peg = (- peg)
   return pattern{name=name, peg=peg}
end

function cinternals.compile_lookat(a, raw, gmr, source, env)
   assert(a, "did not get ast in compile_lookat")
   local name, pos, text, subs, subidx = common.decode_match(a)
   local peg = cinternals.compile_exp(subs[subidx], raw, gmr, source, env).peg
   peg = (# peg)
   return pattern{name=name, peg=peg}
end

function cinternals.compile_sequence(a, raw, gmr, source, env)
   assert(a, "did not get ast in compile_sequence")
   -- sequences from the parser are always binary, with subexps stored at positions 3 and 4
   -- (i.e. just after the source position field)
   -- Regarding debugging... the failure of a[3] is fatal for a[1]
   local name, pos, text, subs, subidx = common.decode_match(a)
   local peg1, peg2
   peg1 = cinternals.compile_exp(subs[subidx], raw, gmr, source, env).peg
   peg2 = cinternals.compile_exp(subs[subidx+1], raw, gmr, source, env).peg
   -- when the first exp is a predicate, it will not consume any input, so we must avoid
   -- concatenating two "boundary" expressions, because boundary*boundary always fails!
   -- note that some quantified exps have their boundary included, and some do not.  but the new
   -- definition of boundary includes looking BACK at whitespace and forward at non-whitespace, so
   -- we can safely append a boundary to a quantified exp when not in raw mode.
   if raw or
      next(subs[subidx])=="negation" or
      next(subs[subidx])=="lookat"
-- or
      -- special case for end of line coming next: don't want to capture any boundary whitespace
      -- between the pattern denoted by identifier and the end of the line
--      (next(subs[subidx+1])=="identifier" and subs[subidx+1].identifier.text=="$")
   then
      return pattern{name=name, peg=peg1 * peg2}
   else
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
   local name, pos, text, subs, subidx = common.decode_match(a)
   if next(subs[subidx])=="range" then
      local r = subs[subidx]
      assert(r, "did not get range ast in compile_charset")
      local rname, rpos, rtext, rsubs, rsubidx = common.decode_match(r)
      assert(not rsubs[rsubidx+2])
      assert(next(rsubs[rsubidx])=="character")
      assert(next(rsubs[rsubidx+1])=="character")
      local cname1, cpos1, ctext1 = common.decode_match(rsubs[rsubidx])
      local cname2, cpos2, ctext2 = common.decode_match(rsubs[rsubidx+1])
      return pattern{name=name, peg=R(common.unescape_string(ctext1)..common.unescape_string(ctext2))}
   elseif next(subs[subidx])=="charlist" then
      local exps = "";
      assert(subs[subidx], "did not get charlist sub in compile_charset")
      local clname, clpos, cltext, clsubs, clsubidx = common.decode_match(subs[subidx])
      for i = clsubidx, #clsubs do
	 local v = clsubs[i]
	 assert(next(v)=="character", "did not get character sub in compile_charset")
	 local cname, cpos, ctext = common.decode_match(v)
	 exps = exps .. common.unescape_string(ctext)
      end
      return pattern{name=name, peg=S(exps)}
   else
      error("Internal error (compiler): Unknown charset type: "..next(subs[subidx]))
   end
end

function cinternals.compile_choice(a, raw, gmr, source, env)
   assert(a, "did not get ast in compile_choice")
   -- The parser returns only binary choice tokens, i.e. a choice bewteen exactly two
   -- expressions. 
   -- Regarding debugging...
   -- 'a' fails if both alternatives fail
   local name, pos, text, subs, subidx = common.decode_match(a)
   local peg1 = cinternals.compile_exp(subs[subidx], raw, gmr, source, env).peg
   local peg2 = cinternals.compile_exp(subs[subidx+1], raw, gmr, source, env).peg
   return pattern{name=name, peg=(peg1+peg2), alternates = { peg1, peg2 }}
end

function cinternals.wrap_peg(pat, name, raw)
   local peg
   if pat.alternates and (not raw) then
      -- The presence of pat.alternates means this pattern came from a CHOICE exp, in which case 
      -- val.peg already holds the compiler result for this node.  But val.peg was calculated 
      -- assuming RAW mode.  So if we are NOT in raw mode, then we must finish the compilation in
      -- a special way.
      peg = ( common.match_node_wrap(C(pat.alternates[1]), name) * boundary ) + ( common.match_node_wrap(C(pat.alternates[2]), name) * boundary )
   else
      peg = common.match_node_wrap(pat.peg, name)
   end
   return peg
end

function cinternals.compile_group(a, raw, gmr, source, env)
   assert(a, "did not get ast in compile_group")
   local name, pos, text, subs, subidx = common.decode_match(a)
   assert(name=="raw" or name=="cooked")
   if name=="raw" then raw=true; else raw=false; end
   assert(not subs[subidx+1])
   local peg = cinternals.compile_exp(subs[subidx], raw, gmr, source, env).peg
   return pattern{name=name, peg=peg}
end

function cinternals.compile_syntax_error(a, raw, gmr, source, env)
   assert(a, "did not get ast in compile_syntax_error")
   error("Compiler called on source code with errors! " .. parse.reveal_exp(a))
end

function cinternals.compile_grammar_rhs(a, raw, gmr, source, env)
   assert(a, "did not get ast in compile_grammar")
   local name, pos, text, subs, subidx = common.decode_match(a)
   assert(name=="grammar_")
   assert(type(subs[subidx])=="table")
   assert(type(source)=="string")
   local gtable = compile.new_env(env)
   local first = subs[subidx]			    -- first rule in grammar
   assert(first, "not getting first rule in compile_grammar")
   local fname, fpos, ftext = common.decode_match(first)
   assert(first and (fname=="assignment_" or fname=="alias_"))

   local rule, id_node, id, exp_node
   
   -- first pass: collect rule names as V() refs into a new env
   for i = subidx, #subs do			    -- for each rule
      local rule = subs[i]
      assert(rule, "not getting rule in compile_grammar")
      local rname, rpos, rtext, rsubs, rsubidx = common.decode_match(rule)
      local id_node = rsubs[rsubidx]		    -- identifier clause
      assert(id_node and next(id_node)=="identifier")
      local iname, ipos, id = common.decode_match(id_node)
      gtable[id] = pattern{name=id, peg=V(id), alias=(rname=="alias_")}
   end						    -- for

   -- second pass: compile right hand sides in gtable environment
   local pats = {}
   local start
   for i = subidx, #subs do			    -- for each rule
      rule = subs[i]
      assert(rule, "not getting rule in compile_grammar")
      local rname, rpos, rtext, rsubs, rsubidx = common.decode_match(rule)
      id_node = rsubs[rsubidx]			    -- identifier clause
      assert(id_node, "not getting id_node in compile_grammar")
      local iname, ipos, id, isubs, isubidx = common.decode_match(id_node)
      if not start then start=id; end		    -- first rule is start rule
      exp_node = rsubs[rsubidx+1]		    -- expression clause
      assert(exp_node, "not getting exp_node in compile_grammar")
      -- flags: not raw, inside grammar
      pats[id] = cinternals.compile_exp(exp_node, false, true, source, gtable)
   end						    -- for

   -- third pass: create the table that will create the LPEG grammar by stripping off the Rosie
   -- pattern records, and wrapping as needed with Cp and C
   local t = {}
   for id, pat in pairs(pats) do		    -- for each rule
      if gtable[id].alias then
	 t[id] = pat.peg
      else
	 t[id] = C(pat.peg)
      end
   end						    -- for
   t[1] = start					    -- first rule is start rule
   local success, peg_or_msg = pcall(P, t)	    -- P(t) while catching errors
   if success then
      return start, pattern{name="grammar", peg=peg_or_msg, ast=a, alias=gtable[t[1]].alias}
   else -- failed
      local rule = peg_or_msg:match("'%w'$")
      table.print(a)
      print(peg_or_msg)
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
      env[name] = pat
   end
end

cinternals.compile_exp_functions = {"compile_exp";
			       raw=cinternals.compile_group;
			       cooked=cinternals.compile_group;
			       choice=cinternals.compile_choice;
			       sequence=cinternals.compile_sequence;
			       negation=cinternals.compile_negation;
			       lookat=cinternals.compile_lookat;
			       identifier=cinternals.compile_identifier;
			       string=cinternals.compile_string;
			       named_charset=cinternals.compile_named_charset;
			       charset=cinternals.compile_charset;
			       quantified_exp=cinternals.compile_quantified_exp;
			       syntax_error=cinternals.compile_syntax_error;
			    }

function cinternals.compile_exp(a, raw, gmr, source, env)
   return common.walk_ast(a, cinternals.compile_exp_functions, raw, gmr, source, env)
end

function compile.expression_p(ast)
   local name, pos, text, subs, subidx = common.decode_match(ast)
   return not (not cinternals.compile_exp_functions[name])
end

function cinternals.compile_assignment(a, raw, gmr, source, env)
   assert(a, "did not get ast in compile_assignment")
   local name, pos, text, subs, subidx = common.decode_match(a)
   assert(name=="assignment_")
   assert(next(subs[subidx])=="identifier")
   assert(type(subs[subidx+1])=="table")			    -- the right side of the assignment
   assert(not subs[subidx+2])
   assert(type(source)=="string")
   local _, ipos, iname = common.decode_match(subs[subidx])
   if env[iname] and not QUIET then
      warn("Compiler: reassignment to identifier " .. iname)
   end
   local pat = cinternals.compile_exp(subs[subidx+1], raw, gmr, source, env)
   -- N.B. If the RHS of the expression is a CHOICE node, then the value we compute here for
   -- pat.peg is only valid when the identifier being bound is later referenced in RAW mode.  If
   -- the identifier is referenced in COOKED mode, then we must ignore pat.peg and use the
   -- pat.alternates value to compute the correct peg.  That computation must be done in
   -- conjunction with match_node_wrap.
   pat.peg = C(pat.peg)
   pat.ast = subs[subidx+1]			    -- expression ast
   env[iname] = pat
end

function cinternals.compile_alias(a, raw, gmr, source, env)
   assert(a, "did not get ast in compile_alias")
   local name, pos, text, subs, subidx = common.decode_match(a)
   assert(name=="alias_")
   assert(type(subidx)=="number")
   assert(next(subs[subidx])=="identifier")
   assert(type(subs[subidx+1]=="table"))	    -- the right side of the assignment
   assert(not subs[subidx+2])
   assert(type(source)=="string")
   local _, pos, alias_name = common.decode_match(subs[subidx])
   if env[alias_name] then
      warn("Compiler: reassignment to alias " .. alias_name)
   end
   local pat = cinternals.compile_exp(subs[subidx+1], raw, gmr, source, env)
   pat.alias=true;
   pat.ast = subs[subidx+1]			    -- expression ast
   env[alias_name] = pat
end

function cinternals.compile_ast(ast, raw, gmr, source, env)
   assert(type(ast)=="table", "Compiler: first argument not an ast: "..tostring(a))
   local functions = {"compile_ast";
		      assignment_=cinternals.compile_assignment;
		      alias_=cinternals.compile_alias;
		      grammar_=cinternals.compile_grammar;
		      exp=cinternals.compile_exp;
		      default=cinternals.compile_exp;
		   }
   return common.walk_ast(ast, functions, raw, gmr, source, env)
end

function cinternals.compile_astlist(astlist, raw, gmr, source, env)
   assert(type(astlist)=="table", "Compiler: first argument not a list of ast's: "..tostring(a))
--   assert(type(astlist[1])=="table", "Compiler: first argument not list of ast's: "..tostring(a))
   assert(type(source)=="string")
   local results = {}
   for _,ast in ipairs(astlist) do
      table.insert(results, (cinternals.compile_ast(ast, raw, gmr, source, env)))
   end
   return results
end

----------------------------------------------------------------------------------------
-- Top-level interface to compiler
----------------------------------------------------------------------------------------

-- Rosie core:
local function core_parse_and_explain(source)
   assert(type(source)=="string", "Compiler: source argument is not a string: "..tostring(source))
   local astlist, errlist = parse.parse(source)
   if #errlist~=0 then
      local msg = "Core parser reports syntax errors:\n"
--      for _,e in ipairs(errlist) do
         local _,e = next(errlist)		    -- explain only FIRST error for now
	 msg = msg .. "\n" .. compile.explain_syntax_error(e, source)
--      end
	 return false, msg
   else -- successful parse
      return astlist
   end
end

function compile.compile(source, env, raw, gmr, parser)
   if not parser then parser = parse_and_explain; end
   local astlist, msg = parser(source)
   if not astlist then return false, msg; end	    -- errors are explained in msg
   assert(type(astlist)=="table")
--   if not next(astlist) then return true, ""; end   -- empty astlist, e.g. from whitespace, comments
   assert(type(env)=="table", "Compiler: environment argument is not a table: "..tostring(env))
   local c = coroutine.create(cinternals.compile_astlist)
   local no_lua_error, results_or_error, error_msg = coroutine.resume(c, astlist, raw, gmr, source, env)
   if no_lua_error then
      -- the last return value, astlist, is only used in compile_command_line_expression
      return results_or_error, error_msg, astlist
   else
      error("Internal error (compiler): " .. tostring(results_or_error) .. " / " .. tostring(error_msg))
   end
end

function compile.compile_command_line_expression(source, env, raw, gmr, parser)
   assert(type(env)=="table", "Compiler: environment argument is not a table: "..tostring(env))
   local result, msg, astlist = compile.compile(source, env, raw, gmr, parser)
   if not result then return result, msg; end
   if (#astlist~=1) then
      local msg = "Error: source did not compile to a single pattern: " .. source
      for i, a in ipairs(astlist) do
	 msg = msg .. "\nPattern " .. i .. ": " .. parse.reveal_ast(a)
      end
      return false, msg
   elseif not compile.expression_p(astlist[1]) then
      -- Statements, e.g. assignments, won't produce a pattern
      local msg = "Error: only expressions can be matched (not statements): " .. source
      return false, msg
   end
   -- one ast will compile to one pattern
   if not (result and result[1] and pattern.is(result[1])) then
      -- E.g. an assignment or alias statement won't produce a pattern
      return false, "Error: expression did not compile to a pattern: " .. source
   end
   -- now we check to see if the expression we are evaluating is an identifier, and therefore does
   -- not have to be anonymous
   local kind, pos, id = common.decode_match(astlist[1])
   local pat = env[id]
   if kind=="identifier" and pattern.is(pat) and (not pat.alias) then
      -- if the user entered an identifier, then we are all set, unless it is an alias, which
      -- by itself may capture nothing and thus should be handled like any other kind of
      -- expression
      return result[1]
   else
      -- if the user entered an expression other than an identifier, we should treat it like it
      -- is the RHS of an assignment statement.  need to give it a name, so we label it "*"
      -- since that can't be an identifier name 
      result[1].peg = C(result[1].peg)
      result[1].peg = cinternals.wrap_peg(result[1], "*", raw)
      result[1].ast = astlist[1]
      return result[1]
   end
end

function compile.core_compile_command_line_expression(source, env)
   return compile.compile_command_line_expression(source, env, false, false, core_parse_and_explain)
end
   
function compile.compile_file(filename, env, raw, gmr)
   local f = io.open(filename);
   if (not f) then
      return false, 'Compiler: cannot open file "'..filename..'"'
   end
   local source = f:read("a")
   f:close()
   if type(source)~="string" then
      return false, 'Compiler: unreadable file "'..filename..'"'
   end
   return compile.compile(source, env, raw, gmr)
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
   local astlist = core_parse_and_explain(source)
   if not astlist then return nil; end		    -- errors have been explained already
   return cinternals.compile_astlist(astlist, raw, gmr, source, env)
end

----------------------------------------------------------------------------------------
-- Low level match functions (user level functions use engines)
----------------------------------------------------------------------------------------

function compile.match_peg(peg, input, start)
   return (peg * Cp()):match(input, start)
end

compile.cinternals = cinternals
return compile
