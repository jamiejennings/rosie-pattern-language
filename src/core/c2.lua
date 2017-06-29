-- -*- Mode: Lua; -*-                                                                             
--
-- c2.lua   RPL 1.1 compiler
--
-- © Copyright Jamie A. Jennings 2017.
-- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
-- AUTHOR: Jamie A. Jennings

-- FUTURE:
--   - Upon error in expression, throw out to compile_block, where the identifier (lhs of
--     binding) can be bound to the error.  Then we go on to try to compile other statements.
-- 

local c2 = {}

local lpeg = require "lpeg"
local locale = lpeg.locale()
local P, V, C, S, R, Cmt, B =
   lpeg.P, lpeg.V, lpeg.C, lpeg.S, lpeg.R, lpeg.Cmt, lpeg.B

local common = require "common"
local novalue = common.novalue
local pattern = common.pattern
local violation = require "violation"
local apply_catch = violation.catch
local recordtype = require "recordtype"
parent = recordtype.parent
local environment = require "environment"
lookup = environment.lookup
bind = environment.bind
local e2 = require "e2"

local function throw(msg, a)
   return violation.throw(violation.compile.new{who='compiler (c2)',
						message=msg,
						ast=a})
end
						
---------------------------------------------------------------------------------------------------
-- Create parser
---------------------------------------------------------------------------------------------------

local function make_parser_from(parse_something, expected_pt_node)
   return function(src, origin, messages)
	     assert(type(src)=="string", "src is " .. tostring(src))
	     assert(origin==nil or type(origin)=="string")
	     assert(type(messages)=="table", "missing messages arg?")
	     local pt, warnings, leftover = parse_something(src)
	     assert(type(warnings)=="table")
	     if not pt then
		local err = violation.syntax.new{who='rpl parser', message=table.concat(warnings, "\n")}
		err.src = src; err.origin = origin
		table.insert(messages, err)
		return false
	     end
	     table.move(warnings, 1, #warnings, #messages+1, messages)
	     assert(type(pt)=="table")
	     assert(pt.type==expected_pt_node, util.table_to_pretty_string(pt, false))
	     if leftover~=0 then
		local msg = "extraneous input after expression: " .. src:sub(-leftover)
		local err = violation.syntax.new{who='rpl parser', message=msg}
		err.src = src; err.origin = origin
		table.insert(messages, err)
		return false
	     end
	     return ast.from_parse_tree(pt)
	  end
 end

function c2.make_parse_block(rplx_preparse, rplx_statements, supported_version)
   local parse_block = p2.make_parse_block(rplx_preparse, rplx_statements, supported_version)
   return make_parser_from(parse_block, "rpl_statements")
end

function c2.make_parse_expression(rplx_expression)
   local parse_expression = p2.make_parse_expression(rplx_expression)
   return make_parser_from(parse_expression, "rpl_expression")
end

c2.dependencies_of = ast.dependencies_of

---------------------------------------------------------------------------------------------------
-- Syntax expander
---------------------------------------------------------------------------------------------------

c2.expand_block = e2.block
c2.expand_expression = e2.expression

---------------------------------------------------------------------------------------------------
-- Compile bindings and expressions
---------------------------------------------------------------------------------------------------

local expression;

local function literal(a, env, messages)
   local str, offense = common.unescape_string(a.value)
   if not str then
      throw("invalid escape sequence in literal: \\" .. offense, a)
   end
   a.pat = pattern.new{name="literal"; peg=P(str); ast=a}
   return a.pat
end

local function sequence(a, env, messages)
   assert(#a.exps > 0, "empty sequence?")
   local peg = expression(a.exps[1], env, messages).peg
   for i = 2, #a.exps do
      peg = peg * expression(a.exps[i], env, messages).peg
   end
   a.pat = pattern.new{name="sequence", peg=peg, ast=a}
   return a.pat
end

local function choice(a, env, messages)
   assert(#a.exps > 0, "empty choice?")
   local peg = expression(a.exps[1], env, messages).peg
   for i = 2, #a.exps do
      peg = peg + expression(a.exps[i], env, messages).peg
   end
   a.pat = pattern.new{name="choice", peg=peg, ast=a}
   return a.pat
end

local function predicate(a, env, messages)
   local peg = expression(a.exp, env, messages).peg
   if a.type=="@" then
      peg = #peg
   elseif a.type=="!" then
      peg = (- peg)
   else
      throw("invalid predicate type: " .. tostring(a.type), a)
   end
   a.pat = pattern.new{name="predicate", peg=peg, ast=a}
   return a.pat
end


-- TODO: Change each "1" below to lookup(env, ".")


local function cs_named(a, env, messages)
   local peg = locale[a.name]
   if not peg then
      throw("unknown named charset: " .. a.name, a)
   end
   -- The posix character sets are ascii-only, so the "1-peg" below is ok.
   a.pat = pattern.new{name="cs_named", peg=((a.complement and 1-peg) or peg), ast=a}
   return a.pat
end

-- TODO: This impl works only for single byte chars!
local function cs_range(a, env, messages)
   local c1, offense1 = common.unescape_charlist(a.first)
   local c2, offense2 = common.unescape_charlist(a.last)
   if (not c1) or (not c2) then
      throw("invalid escape sequence in character set: \\" ..
	    (c1 and offense2) or offense1,
	 a)
   end
   local peg = R(c1..c2)
   a.pat = pattern.new{name="cs_range", peg=(a.complement and (1-peg)) or peg, ast=a}
   return a.pat
end

-- FUTURE optimization: All the single-byte chars can be put into one call to lpeg.S().
-- FUTURE optimization: The multi-byte chars can be organized by common prefix. 
function cs_list(a, env, messages)
   assert(#a.chars > 0, "empty character set list?")
   local alternatives
   for i, c in ipairs(a.chars) do
      local char, offense = common.unescape_charlist(c)
      if not char then
	 throw("invalid escape sequence in character set: \\" .. offense, a)
      end
      if not alternatives then alternatives = P(char)
      else alternatives = alternatives + P(char); end
   end -- for
   a.pat = pattern.new{name="cs_list",
		      peg=(a.complement and (1-alternatives) or alternatives),
		      ast=a}
   return a.pat
end

local cexp;

function cs_exp(a, env, messages)
   if ast.cs_exp.is(a.cexp) then
      if not a.complement then
	 -- outer cs_exp does not affect semantics, so drop it
	 return cs_exp(a.cexp)
      else
	 -- either: inner cs_exp does not affect semantics, so drop it,
	 -- or: complement of a complement cancels out.
	 local new = ast.cs_exp{complement=(not a.cexp.complement), cexp=a.cexp.cexp, s=a.s, e=e.s}
	 return cs_exp(new, env, messages)
      end
   elseif ast.cs_union.is(a.cexp) then
      assert(#a.cexp.cexps > 0, "empty character set union?")
      local alternatives = expression(a.cexp.cexps[1]).peg
      for i = 2, #a.cexp.cexps do
	 alternatives = alternatives + expression(a.cexp.cexps[i]).peg
      end
      a.pat = pattern.new{name="cs_exp",
			 peg=((a.complement and (1-alternatives)) or alternatives),
			 ast=a}
      return a.pat
   elseif ast.cs_intersection.is(a.cexp) then
      throw("character set intersection is not implemented", a)
   elseif ast.cs_difference.is(a.cexp) then
      throw("character set difference is not implemented", a)
   elseif ast.simple_charset_p(a.cexp) then
      local p = expression(a.cexp, env, messages)
      a.pat = pattern.new{name="cs_exp", peg=((a.complement and (1-p.peg)) or p.peg), ast=a}
      return a.pat
   else
      assert(false, "unknown cexp inside cs_exp", a)
   end
end

local function wrap_pattern(pat, name)
   if pat.uncap then
      -- If pat.uncap exists, then pat.peg is already wrapped in a capture.  In order to wrap pat
      -- with a capture called 'name', we start with pat.uncap.  Here's a case where this happens:
      -- We must have an assignment like 'p1 = p2' where p2 is not an alias.  RPL semantics are
      -- that p1 must capture the same as p2, but the output should be labeled p1.
      pat.peg = common.match_node_wrap(pat.uncap, name)
   else
      -- If there is no pat.uncap, then pat.peg is NOT wrapped in a capture, so we can simply wrap
      -- it with a capture called 'name'.
      pat.uncap = pat.peg
      pat.peg = common.match_node_wrap(pat.peg, name)
   end
end

local function throw_grammar_error(a, message)
   local maybe_rule = message:match("'%w'$")
   local rule_explanation = (maybe_rule and "in pattern "..maybe_rule.." of:") or ""
   local fmt = "%s"
   common.note("grammar: entering throw_grammar_error: " .. message)
   if message:find("may be left recursive") then
      throw(string.format(fmt, message), a)
   end
   throw("peg compilation error: " .. message, a)
end

local function grammar(a, env, messages)
   local gtable = environment.extend(env)
   -- First pass: collect rule names as V() refs into a new env
   for _, rule in ipairs(a.rules) do
      assert(ast.binding.is(rule))
      assert(not rule.ref.packagename)
      assert(type(rule.ref.localname)=="string")
      local id = rule.ref.localname
      bind(gtable, id, pattern.new{name=id, peg=V(id), alias=rule.is_alias})
      common.note("grammar: binding " .. id)
   end
   -- Second pass: compile right hand sides in gtable environment
   local pats = {}
   local start
   for _, rule in ipairs(a.rules) do
      local id = rule.ref.localname
      if not start then start=id; end		    -- first rule is start rule
      common.note("grammar: compiling " .. tostring(rule.exp))
      pats[id] = expression(rule.exp, gtable, messages)
      if (not rule.is_alias) then wrap_pattern(pats[id], id); end
   end -- for
   -- Third pass: create the table that will create the LPEG grammar 
   local t = {}
   for id, pat in pairs(pats) do t[id] = pat.peg; end
   t[1] = start					    -- first rule is start rule
   local uncap_peg
   local success, peg_or_msg = pcall(P, t)	    -- P(t) while catching errors
   common.note("grammar: lpeg.P() produced " .. tostring(success) .. ", " .. tostring(peg_or_msg))
   if success then
      local aliasflag = lookup(gtable, t[1]).alias
      if not aliasflag then
	 assert(pats[start].uncap)
	 t[start] = pats[start].uncap
	 success, uncap_peg = pcall(P, t)
      end
   end
   if (not success) then
      assert(type(peg_or_msg)=="string",
	  "Internal error (compiler) while reporting an error in a grammar")
      throw_grammar_error(a, peg_or_msg)
   end
   a.pat = pattern.new{name="grammar",
		      peg=peg_or_msg,
		      uncap=(aliasflag and nil) or uncap_peg,
		      ast=a,
		      alias=aliasflag}
   return a.pat
end

-- We cannot just run peg:match("") because a lookahead expression will return nil (i.e. it will
-- not match the empty string), even though it cannot be put into a loop (because it consumes no
-- input).
local function matches_empty(peg)
   local ok, msg = pcall(function() return peg^1 end)
   return (not ok) and msg:find("loop body may accept empty string")
end

-- local function repetition(a, env, messages)
--    local boundary_pattern, boundary
--    if a.cooked then
--       boundary_pattern = lookup(env, common.boundary_identifier)
--       if not pattern.is(boundary_pattern) then
-- 	 throw("a very unusual situation occurred in which the boundary identifier, " ..
-- 	       common.boundary_identifier, ", is not bound to a pattern", a)
--       end
--       boundary = boundary_pattern.peg
--       assert(boundary)
--    end -- if a.cooked
--    local epat = expression(a.exp, env, messages)
--    a.exp.pat = epat
--    local epeg = epat.peg
--    if matches_empty(epeg) then
--       throw("pattern being repeated can match the empty string", a)
--    end
--    local qpeg
--    local min, max, cooked = a.min, a.max, a.cooked
--    if (not min) then min = 0; end		    -- {,max}
--    if (not max) then
--       if min==1 then				    -- +
-- 	 if cooked then qpeg = (epeg * boundary)^1
-- 	 else qpeg = epeg^1; end
--       elseif min==0 then			    -- *
-- 	 if cooked then qpeg = (epeg * (boundary * epeg)^0)^-1
-- 	 else qpeg = epeg^0; end
--       else
-- 	 assert(type(min)=="number", "min not a number? " .. tostring(min))
-- 	 assert(min > 0)
-- 	 if cooked then qpeg = (epeg * (boundary * epeg)^(min-1))
-- 	 else qpeg = epeg^min; end		    -- {min,}
--       end -- switch on min
--    else -- have a max and a min value
--       if min > max then
-- 	 throw("invalid repetition (min must be greater than max)", a)
--       elseif (max < 1) then
-- 	 throw("invalid repetition (max must be greater than zero)", a)
--       elseif min < 0 then
-- 	 throw("invalid repetition (min must be greater than or equal to zero)", a)
--       end
--       -- Here's where things get interesting, because we must match at least min copies of
--       -- epeg, and at most max.
--       if min==0 then
-- 	 if max==1 then
-- 	    qpeg = epeg^-1
-- 	 else
-- 	    assert(max > 1)
-- 	    if cooked then
-- 	       qpeg = (epeg * (boundary * epeg)^(1-max))^-1
-- 	    else
-- 	       qpeg = epeg^(-max)
-- 	    end
-- 	 end
--       else
-- 	 assert(min > 0)
-- 	 qpeg = epeg
-- 	 for i=1, (min-1) do
-- 	    qpeg = qpeg * ((cooked and (boundary * epeg)) or epeg)
-- 	 end -- for
-- 	 if (min-max) < 0 then
-- 	    qpeg = qpeg * ((cooked and (boundary * epeg) or epeg)^(min-max))
-- 	 else
-- 	    assert(min==max)
-- 	 end
--       end -- switch on min
--    end -- switch on max
--    -- return peg being quantified, quantified peg, whether boundary was appended, quantifier name, min, max
--    a.pat = pattern.new{name="repetition", peg=qpeg, ast=a}
--    return a.pat
-- end

local function rep(a, env, messages)
   local epat = expression(a.exp, env, messages)
   local epeg = epat.peg
   if matches_empty(epeg) then
      throw("pattern being repeated can match the empty string", a)
   end
   a.exp.pat = epat
   if ast.atleast.is(a) then
      a.pat = pattern.new{name="atleast", peg=(epeg)^(a.min), ast=a}
   elseif ast.atmost.is(a) then
      a.pat = pattern.new{name="atmost", peg=(epeg)^(-a.max), ast=a}
   else
      assert(false, "invalid ast node dispatched to 'rep': " .. tostring(a))
   end
   return a.pat
end

local function ref(a, env, messages)
   local pat = lookup(env, a.localname, a.packagename)
   if (not pat) then throw("unbound identifier", a); end
   if not(pattern.is(pat)) then
      local name = (a.packagename and (a.packagename .. ".") or "") .. a.localname
      throw("type mismatch: expected a pattern, but '" .. name .. "' is bound to " .. tostring(pat), a)
   end
   a.pat = pattern.new{name=a.localname, peg=pat.peg, alias=pat.alias, ast=pat.ast, raw=pat.raw, uncap=pat.uncap}
   if a.packagename and (not pat.alias) then
      -- Here, pat was wrapped with only a local name when its module was compiled.  We need to
      -- rewrap using the fully qualified name, because the code we are now compiling uses the
      -- fully qualified name to refer to this value.
      assert(pat.uncap)
      a.pat.peg = common.match_node_wrap(pat.uncap, a.packagename .. "." .. a.localname)
   end
   return a.pat
end

local dispatch = { [ast.literal] = literal,
		   [ast.sequence] = sequence,
		   [ast.choice] = choice,
		   [ast.ref] = ref,
		   [ast.cs_exp] = cs_exp,
		   [ast.cs_named] = cs_named,
		   [ast.cs_range] = cs_range,
		   [ast.cs_list] = cs_list,
		   --[ast.repetition] = repetition,
		   [ast.atmost] = rep,
		   [ast.atleast] = rep,
		   [ast.predicate] = predicate,
		   [ast.grammar] = grammar,
		}

-- the forward reference declares 'expression' to be local
function expression(a, env, messages)
   local compile = dispatch[parent(a)]
   if (not compile) then
      throw("invalid expression: " .. tostring(a), a)
   end
   a.pat = compile(a, env, messages)
   return a.pat
end

local function compile_expression(exp, env, messages)
   local ok, value, err = apply_catch(expression, exp, env, messages)
   if not ok then
      local full_message =
	 "error in compile_expression:" ..
	 tostring(value) .. "\n"
      for _,v in ipairs(messages) do
	 full_message = full_message .. tostring(v) .. "\n"
      end
      assert(false, full_message)
   elseif not value then
      assert(recordtype.parent(err))
      table.insert(messages, err)		    -- enqueue violation object
      return false
   end
   return value
end

-- 'c2.compile_expression' compiles a top-level expression for matching.  If the expression is
-- simply a reference, the match output will have the name of the referenced pattern.  If the
-- expression is a reference to an alias, or if the expression is not a reference at all, then the
-- match output will have the name "*" (meaning "anonymous") at the top level.
function c2.compile_expression(a, env, messages)
   local pat = compile_expression(a, env, messages)
   if not pat then return false; end		    -- error will be in messages
   if pat and (not pattern.is(pat)) then
      local msg =
	 "type error: expression did not compile to a pattern, instead got " .. tostring(pat)
      table.insert(messages,
		   violation.compile.new{who='compile expression', message=msg, ast=a})
      return false
   end
   local peg, name = pat.peg, pat.name
   if ast.ref.is(a) then
      if pat.alias then
	 pat.alias = false
	 pat.peg = common.match_node_wrap(pat.peg, "*")
      end
   else -- not a reference
      name = "*"				    -- anonymous pattern
      if pat.uncap then peg = pat.uncap; end
      pat.alias = false
      pat.peg = common.match_node_wrap(peg, name)
   end
   return pat
end

---------------------------------------------------------------------------------------------------
-- Compile block
---------------------------------------------------------------------------------------------------

-- Compile all the statements in the block.  Any imports were loaded during the syntax expansion
-- phase, in order to access macro definitions.
function c2.compile_block(a, pkgenv, messages)
   assert(ast.block.is(a))
   -- Step 1: For each lhs, bind the identifier to 'novalue'.
   -- TODO: Ensure each lhs appears only once in a.stmts.
   for _, b in ipairs(a.stmts) do
      assert(ast.binding.is(b))
      local ref = b.ref
      assert(not ref.packagename)
      if environment.lookup(pkgenv, ref.localname) then
	 common.note("Rebinding " .. ref.localname)
      else
	 common.note("Creating novalue binding for " .. ref.localname)
      end
      bind(pkgenv, ref.localname, novalue.new{exported=true, ast=b})
   end -- for
   -- Step 2: Compile the rhs (expression) for each binding.  
   -- TODO: If an exp depends on a 'novalue', return 'novalue'.
   -- TODO: Repeat step 2 until either every lhs is bound to an actual value (or error), or an
   --       entire pass through a.stmts fails to change any binding.
   for _, b in ipairs(a.stmts) do
      local ref, exp = b.ref, b.exp
      local pat = compile_expression(exp, pkgenv, messages)

      if pat then 
	 -- TODO: need a proper error message
	 if type(pat)~="table" then
	    io.stderr:write("    BUT DID NOT GET A PATTERN: ", tostring(pat), "\n")
	 end
	 if (not b.is_alias) then wrap_pattern(pat, ref.localname); end
	 pat.alias = b.is_alias
	 if b.is_local then pat.exported = false; end
	 bind(pkgenv, ref.localname, pat)
      else
	 return false
      end
   end -- for

   -- Step 3: 

   return true
end

return c2
