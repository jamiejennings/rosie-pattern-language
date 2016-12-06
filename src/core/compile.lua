---- -*- Mode: Lua; -*-                                                                           
----
---- compile.lua   Compile Rosie Pattern Language to LPEG
----
---- © Copyright IBM Corporation 2016.
---- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
---- AUTHOR: Jamie A. Jennings


local compile = {}				    -- exported top level interface
local cinternals = {}				    -- exported interface to compiler internals

-- forward reference
parse_and_explain = function(...)
		       error("Self-hosted parser not loaded")
		    end

local common = require "common"
local parse = require "parse"			    -- RPL parser and AST functions
local lpeg = require "lpeg"
local util = require "util"
require "recordtype"
local unspecified = recordtype.unspecified
local syntax = require "syntax"

local P, V, C, S, R, Ct, Cg, Cp, Cc, Cmt, B =
   lpeg.P, lpeg.V, lpeg.C, lpeg.S, lpeg.R, lpeg.Ct, lpeg.Cg, lpeg.Cp, lpeg.Cc, lpeg.Cmt, lpeg.B

local locale = lpeg.locale()
local boundary = common.boundary

----------------------------------------------------------------------------------------
-- Compile-time error reporting
----------------------------------------------------------------------------------------

local function explain_quantified_limitation(a, source, maybe_rule)
   assert(a, "did not get ast in explain_quantified_limitation")
   local name, errpos, text = common.decode_match(a)
   local line, pos, lnum = util.extract_source_line_from_pos(source, errpos)
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
   local line, pos, lnum = util.extract_source_line_from_pos(source, errpos)
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
   local line, pos, lnum = util.extract_source_line_from_pos(source, errpos)
   local msg = "Compile error: reference to undefined identifier: " .. text .. "\n" ..
      string.format("At line %d:\n", lnum) ..
      string.format("%s\n", line) ..
      string.rep(" ", pos-1) .. "^"
   coroutine.yield(false, msg)				    -- throw
end

local function explain_undefined_charset(a, source)
   assert(a, "did not get ast in explain_undefined_charset")
   local _, errpos, name, subs = common.decode_match(a)
   local line, pos, lnum = util.extract_source_line_from_pos(source, errpos)
   local msg = "Compile error: named charset not defined: " .. name .. "\n" ..
      string.format("At line %d:\n", lnum) ..
      string.format("%s\n", line) ..
      string.rep(" ", pos-1) .. "^"
   coroutine.yield(false, msg)				    -- throw
end

local function explain_unknown_quantifier(a, source)
   assert(a, "did not get ast in explain_unknown_quantifier")
   local name, errpos, text, subs = common.decode_match(a)
   local line, pos, lnum = util.extract_source_line_from_pos(source, errpos)
   local q = subs[2]				    -- IS THIS RIGHT?
   local msg = "Compile error: unknown quantifier: " .. q .. "\n" ..
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

-- Regarding debugging... a quantified exp fails as soon as:
-- e^0 == e* can never fail, because it can match the empty string.
-- e^1 == e+ fails when as soon as the initial attempt to match e fails.
-- e^-1 == e? can never fail because it can match the empty string
-- e{n,m} == (e * e ...)*e^(m-n) will fail when any of the sequence fails.

function cinternals.process_quantified_exp(a, gmr, source, env)
   assert(a, "did not get ast in process_quantified_exp")
   local name, pos, text, subs = common.decode_match(a)
   assert(name=="new_quantified_exp")
   local qpeg, min, max
   local append_boundary = true
   local expname, expbody = next(subs[1])
   local raw = (expname=="raw_exp")
   if raw then
      expname, expbody = next(expbody.subs[1])
      append_boundary = false
   end
   local e = cinternals.compile_exp(subs[1], gmr, source, env)
   local epeg = e.peg
   if (not gmr) and matches_empty(epeg) then
      explain_quantified_limitation(a, source);
   end
   local q = subs[2]
   assert(q, "not getting quantifier clause in process_quantified_exp")
   local qname, qpos, qtext, qsubs = common.decode_match(q)
   if qname=="plus" then
      if append_boundary then qpeg=(epeg * boundary)^1
      else qpeg=epeg^1; end
      min=1; max=nil
   elseif qname=="star" then
      if append_boundary then qpeg = (epeg * (boundary * epeg)^0)^-1
      else qpeg=epeg^0; end
      min=0; max=nil
   elseif qname=="question" then
      qpeg=epeg^-1
      min=0; max=1
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

function cinternals.compile_new_quantified_exp(a, gmr, source, env)
   assert(a, "did not get ast in compile_cooked_quantified_exp")
   local epeg, qpeg, append_boundary, qname, min, max = cinternals.process_quantified_exp(a, gmr, source, env)
   return pattern{name=qname, peg=qpeg, ast=a};
end

function cinternals.compile_literal(a, gmr, source, env)
   assert(a, "did not get ast in compile_literal")
   local name, pos, text = common.decode_match(a)
   local str = common.unescape_string(text)
   return pattern{name=name; peg=P(str); ast=a}
end

function cinternals.compile_ref(a, gmr, source, env)
   assert(a, "did not get ast in compile_ref")
   local reftype, pos, name = common.decode_match(a)
   local pat = env[name]
   if (not pat) then explain_undefined_identifier(a, source); end -- throw
   assert(pattern.is(pat), "Did not get a pattern: "..tostring(pat))
   return pattern{name=name, peg=pat.peg, alias=pat.alias, ast=pat.ast, raw=pat.raw, uncap=pat.uncap}
end

function cinternals.compile_predicate(a, gmr, source, env)
   assert(a, "did not get ast in compile_predicate")
   local name, pos, text, subs = common.decode_match(a)
   local peg = cinternals.compile_exp(subs[2], gmr, source, env).peg
   local pred_clause = subs[1]
   local pred_name = next(pred_clause)
   if pred_name=="negation" then peg = (- peg)
   elseif pred_name=="lookat" then peg = (# peg)
   else error("Internal compiler error: unknown predicate type: " .. tostring(pred_name))
   end
   return pattern{name=pred, peg=peg, ast=a}
end

-- Sequences from the parser are always binary, i.e. with 2 subs.
-- Regarding debugging: the failure of subs[1] is fatal for a.
function cinternals.compile_sequence(a, gmr, source, env)
   assert(a, "did not get ast in compile_sequence")
   local name, pos, text, subs = common.decode_match(a)
   local peg1, peg2
   peg1 = cinternals.compile_exp(subs[1], gmr, source, env).peg
   peg2 = cinternals.compile_exp(subs[2], gmr, source, env).peg
   return pattern{name=name, peg=peg1 * peg2, ast=a}
end
   
function cinternals.compile_named_charset(a, gmr, source, env)
   assert(a, "did not get ast in compile_named_charset")
   local name, pos, text, subs = common.decode_match(a)
   local complement
   if subs then					    -- subs not present from core parser
      complement = (next(subs[1])=="complement")
      if complement then assert(subs[2] and (next(subs[2])=="name")); end
      name, pos, text, subs = common.decode_match((complement and subs[2]) or subs[1])
   end
   local pat = locale[text]
   if not pat then
      explain_undefined_charset(a, source)
   end
   return pattern{name=name, peg=((complement and 1-pat) or pat), ast=a}
end

function cinternals.compile_range_charset(a, gmr, source, env)
   assert(a, "did not get ast in compile_range_charset")
   local rname, rpos, rtext, rsubs = common.decode_match(a)
   assert(rsubs and rsubs[1])
   local complement = (next(rsubs[1])=="complement")
   if complement then
      assert(rsubs[2] and (next(rsubs[2])=="character"))
      assert(rsubs[3] and (next(rsubs[3])=="character"))
   else
      assert(next(rsubs[1])=="character")
      assert(rsubs[2] and (next(rsubs[2])=="character"))
   end
   local cname1, cpos1, ctext1 = common.decode_match(rsubs[(complement and 2) or 1])
   local cname2, cpos2, ctext2 = common.decode_match(rsubs[(complement and 3) or 2])
   peg = R(common.unescape_string(ctext1)..common.unescape_string(ctext2))
   return pattern{name=name,
		  peg=(complement and (1-peg)) or peg,
		  ast=a}
end

function cinternals.compile_charlist(a, gmr, source, env)
   assert(a, "did not get ast in compile_charlist")
   local clname, clpos, cltext, clsubs = common.decode_match(a)
   local exps = "";
   assert((type(clsubs)=="table") and clsubs[1], "no sub-matches in charlist!")
   local complement = (next(clsubs[1])=="complement")
   for i = (complement and 2) or 1, #clsubs do
      local v = clsubs[i]
      assert(next(v)=="character", "did not get character sub in compile_charlist")
      local cname, cpos, ctext = common.decode_match(v)
      exps = exps .. common.unescape_string(ctext)
   end
   return pattern{name=name, peg=((complement and (1-S(exps))) or S(exps)), ast=a}
end

function cinternals.compile_charset(a, gmr, source, env)
   assert(a, "did not get ast in compile_charset")
   local name, pos, text, subs = common.decode_match(a)
   if next(subs[1])=="range" then
      return cinternals.compile_range_charset(subs[1], gmr, source, env)
   elseif next(subs[1])=="charlist" then
      return cinternals.compile_charlist(subs[1], gmr, source, env)
   else
      error("Internal error (compiler): Unknown charset type: "..next(subs[1]))
   end
end

-- Choice ASTs will have exactly two alternatives
-- Regarding debugging... 'a' fails only if both alternatives fail
function cinternals.compile_choice(a, gmr, source, env)
   assert(a, "did not get ast in compile_choice")
   local name, pos, text, subs = common.decode_match(a)
   local peg1 = cinternals.compile_exp(subs[1], gmr, source, env).peg
   local peg2 = cinternals.compile_exp(subs[2], gmr, source, env).peg
   return pattern{name=name, peg=(peg1+peg2), ast=a}
end

function cinternals.compile_raw_exp(a, gmr, source, env)
   assert(a, "did not get ast in compile_raw_exp")
   local name, pos, text, subs = common.decode_match(a)
   assert(name=="raw_exp")
   assert(not subs[2])
   local pat = cinternals.compile_exp(subs[1], gmr, source, env)
   return pattern{name=name, peg=pat.peg, ast=pat.ast}
end

function cinternals.compile_syntax_error(a, gmr, source, env)
   assert(a, "did not get ast in compile_syntax_error")
   error("Compiler called on source code with errors! " .. parse.reveal_exp(a))
end

function cinternals.compile_grammar_rhs(a, gmr, source, env)
   assert(a, "did not get ast in compile_grammar_rhs")
   local name, pos, text, subs = common.decode_match(a)
   assert(name=="grammar_" or name=="new_grammar")
   assert(type(subs[1])=="table")
   local gtable = common.new_env(env)
   local first = subs[1]			    -- first rule in grammar
   assert(first, "not getting first rule in compile_grammar_rhs")
   local fname, fpos, ftext = common.decode_match(first)
   assert(first and (fname=="binding"))

   local rule, id_node, id, exp_node
   
   -- first pass: collect rule names as V() refs into a new env
   for i = 1, #subs do			    -- for each rule
      local rule = subs[i]
      assert(rule, "not getting rule in compile_grammar_rhs")
      local rname, rpos, rtext, rsubs = common.decode_match(rule)
      assert(rname=="binding")
      local id_node = rsubs[1]			    -- identifier clause
      assert(id_node and next(id_node)=="identifier")
      local iname, ipos, id = common.decode_match(id_node)
      -- the first rule must be set to true to match correctly
      -- XXX: unsure why this is, needs better explanation
      local alias_flag = first==subs[i] and true or rule.binding.capture
      gtable[id] = pattern{name=id, peg=V(id), alias=alias_flag}
   end						    -- for

   -- second pass: compile right hand sides in gtable environment
   local pats = {}
   local start
   for i = 1, #subs do			    -- for each rule
      rule = subs[i]
      assert(rule, "not getting rule in compile_grammar_rhs")
      local rname, rpos, rtext, rsubs = common.decode_match(rule)
      id_node = rsubs[1]			    -- identifier clause
      assert(id_node, "not getting id_node in compile_grammar_rhs")
      local iname, ipos, id, isubs = common.decode_match(id_node)
      if not start then start=id; end		    -- first rule is start rule
      exp_node = rsubs[2]			    -- expression clause
      assert(exp_node, "not getting exp_node in compile_grammar_rhs")
      pats[id] = cinternals.compile_exp(exp_node, true, source, gtable) -- gmr flag is true 
   end -- for

   -- third pass: create the table that will create the LPEG grammar by stripping off the Rosie
   -- pattern records, and wrapping as needed with lpeg.C
   local t = {}
   for id, pat in pairs(pats) do t[id] = pat.peg; end
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

function cinternals.compile_grammar(a, gmr, source, env)
   local name, pat = cinternals.compile_grammar_rhs(a, gmr, source, env)
   -- if no pattern returned, then errors were already explained
   if pat then
      local msg
      if env[name] then msg = "Warning: reassignment to identifier " .. name; end
      env[name] = pat
      return pat, msg
   end
end

function cinternals.compile_capture(a, gmr, source, env)
   assert(a, "did not get ast in compile_capture")
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

   pat = cinternals.compile_exp(captured_exp, gmr, source, env)
   pat.name = cap_name
   if pat.uncap then
      -- In this case, we are capturing a reference that is itself a capture.  So what we want to
      -- do is a re-capture, i.e. ignore the existing capture.
      pat.peg = common.match_node_wrap(C(pat.uncap), reftext)
   else
      pat.uncap = pat.peg
      pat.peg = common.match_node_wrap(C(pat.peg), reftext)
   end
   return pat
end

cinternals.compile_exp_functions = {"compile_exp";
				    capture=cinternals.compile_capture;	    
				    ref=cinternals.compile_ref;
				    predicate=cinternals.compile_predicate;
				    raw_exp=cinternals.compile_raw_exp;
				    choice=cinternals.compile_choice;
				    sequence=cinternals.compile_sequence;
				    literal=cinternals.compile_literal;
				    named_charset=cinternals.compile_named_charset;
				    range=cinternals.compile_range_charset;
				    charlist=cinternals.compile_charlist;
				    charset=cinternals.compile_charset; -- ONLY USED IN CORE
				    new_quantified_exp=cinternals.compile_new_quantified_exp;
				    syntax_error=cinternals.compile_syntax_error;
				 }

function cinternals.compile_exp(a, gmr, source, env)
   return common.walk_ast(a, cinternals.compile_exp_functions, gmr, source, env)
end

function compile.expression_p(ast)
   local name, pos, text, subs = common.decode_match(ast)
   return not (not cinternals.compile_exp_functions[name])
end

local boundary_ast = common.create_match("ref", 0, common.boundary_identifier)
local looking_at_boundary_ast = common.create_match("predicate",
						    0,
						    "@/generated/",
						    common.create_match("lookat", 0, "@/generated/"),
						    boundary_ast)

function cinternals.compile_binding(a, gmr, source, env)
   assert(a, "did not get ast in compile_binding")
   local name, pos, text, subs = common.decode_match(a)
   local lhs, rhs = subs[1], subs[2]
   assert(next(lhs)=="identifier")
   assert(type(rhs)=="table")			    -- the right side of the assignment
   assert(not subs[3])
   assert(type(source)=="string")
   assert(a.binding and (type(a.binding.capture)=="boolean"))
   local _, ipos, iname = common.decode_match(lhs)
   local pat = cinternals.compile_rhs(rhs, gmr, source, env, iname)
   pat.alias = (not a.binding.capture)
   local msg
   if env[iname] then msg = "Warning: reassignment to identifier " .. iname; end
   env[iname] = pat
   return pat, msg
end

function cinternals.compile_rhs(a, gmr, source, env, iname)
   assert(type(a)=="table", "did not get ast in compile_rhs: " .. tostring(a))
   if not compile.expression_p(a) then
      local msg = string.format('Compile error: expected an expression, but received %q',
				parse.reveal_ast(a))
      error(msg)
   end
   local pat = cinternals.compile_exp(a, gmr, source, env)
   local rhs_name, rhs_body = next(a)
   pat.raw = ((rhs_name=="raw_exp") or
	      ((rhs_name=="capture") and (next(rhs_body.subs[2])=="ref") and pat.raw) or
	      ((rhs_name=="ref") and pat.raw))
   pat.ast = a;
   return pat
end

function cinternals.compile_ast(ast, source, env)
   assert(type(ast)=="table", "Compiler: first argument not an ast: "..tostring(ast))
   local functions = {"compile_ast";
		      binding=cinternals.compile_binding;
		      new_grammar=cinternals.compile_grammar;
		      exp=cinternals.compile_exp;
		      default=cinternals.compile_exp;
		   }
   return common.walk_ast(ast, functions, false, source, env)
end


----------------------------------------------------------------------------------------
-- Top-level interface to compiler
----------------------------------------------------------------------------------------

local function compile_astlist(astlist, source, env)
   assert(type(astlist)=="table", "Compiler: first argument not a list of ast's: "..tostring(a))
   assert(type(source)=="string")
   local results, messages = {}, {}
   for i,a in ipairs(astlist) do
      results[i], messages[i] = cinternals.compile_ast(a, source, env)
      if not messages[i] then messages[i] = false; end -- keep messages a proper list: no nils
   end
   return results, messages
end

function cinternals.compile_astlist(astlist, source, env)
 local c = coroutine.create(compile_astlist)
 local no_lua_error, results, messages = coroutine.resume(c, astlist, source, env)
   if no_lua_error then
      return results, messages			    -- messages may contain compiler warnings
   else
      error("Internal error (compiler): " .. tostring(results))
   end
end

compile.parser = parse.core_parse_and_explain;	    -- Using this as a dynamic variable

function compile.compile_source(source, env)
   local astlist, original_astlist = compile.parser(source)
   if not astlist then return false, original_astlist; end -- original_astlist is msg
   assert(type(astlist)=="table")
   assert(type(original_astlist)=="table")
   assert(type(env)=="table", "Compiler: environment argument is not a table: "..tostring(env))
   local results, messages = cinternals.compile_astlist(astlist, source, env)
   if results then
      assert(type(messages)=="table")
      foreach(function(pat, oast) pat.original_ast=oast; end, results, original_astlist)
      return results, messages			    -- message may contain compiler warnings
   else
      assert(type(messages)=="string")
      return false, messages			    -- message is a string in this case
   end
end

function compile.compile_match_expression(source, env)
   assert(type(env)=="table", "Compiler: environment argument is not a table: "..tostring(env))
   local astlist, original_astlist = compile.parser(source)
   if (not astlist) then
      return false, original_astlist		    -- original_astlist is msg
   end
   assert(type(astlist)=="table")
   -- After adding support for semi-colons to end statements, can change this restriction to allow
   -- arbitrary statements, followed by an expression, like scheme's 'begin' form.
   if (#astlist~=1) then
      local msg = "Error: source did not compile to a single pattern: " .. source
      for i, a in ipairs(astlist) do
	 msg = msg .. "\nPattern " .. i .. ": " .. parse.reveal_ast(a)
      end
      return false, msg
   elseif not compile.expression_p(astlist[1]) then
      local msg = "Error: only expressions can be matched (not statements): " .. source
      return false, msg
   end
   -- Check to see if the expression is a reference
   local name, pos, text, subs = common.decode_match(astlist[1])
   local pat
   if (name=="ref") then
      pat = env[text]
   end
   -- Compile the expression
   local results, msg = compile.compile_source(source, env)
   if (type(results)~="table") or (not pattern.is(results[1])) then -- compile-time error
      return false, msg
   end
   local result = results[1]
   if pat then result.alias = pat.alias; end
   if not (pat and (not pat.alias)) then
      -- If the user entered an identifier, then we are all set, unless it is an alias, which
      -- by itself may capture nothing and thus should be handled like any other kind of
      -- expression.  
      -- If the user entered an expression other than an identifier, we should treat it like it
      -- is the RHS of an assignment statement.  Need to give it a name, so we label it "*"
      -- since that can't be an identifier name.
      result.peg = common.match_node_wrap(C(result.peg), "*")
   end
   return result
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
   -- Intentionally ignoring the value of compile.parse, we ensure the use of
   -- core_parse_and_explain for parsing the Rosie rpl.
   local astlist, msg = parse.core_parse_and_explain(source)
   if not astlist then error("Error parsing core rpl definition: " .. msg); end
   local results, messages = cinternals.compile_astlist(astlist, source, env)
   if not results then
      error("Error compiling core rpl definition: " .. messages)
   else
      return true, messages
   end
end


compile.cinternals = cinternals
return compile
