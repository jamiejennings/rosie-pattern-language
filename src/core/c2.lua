-- -*- Mode: Lua; -*-                                                                             
--
-- c2.lua   RPL 1.1 compiler
--
-- © Copyright Jamie A. Jennings 2017.
-- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
-- AUTHOR: Jamie A. Jennings

-- FUTURE:
--   - Upon error in compile_expression, throw out to compile_block, where the identifier (lhs of
--     binding) can be bound to the error.  Then we go on to try to compile other statements.
-- 

local c2 = {}

local lpeg = require "lpeg"
local locale = lpeg.locale()
local P, V, C, S, R, Cmt, B =
   lpeg.P, lpeg.V, lpeg.C, lpeg.S, lpeg.R, lpeg.Cmt, lpeg.B

local common = require "common"
local throw = common.throw
local apply_catch = common.apply_catch
local novalue = common.novalue
local pattern = common.pattern
local throw = common.throw_error
local recordtype = require "recordtype"
parent = recordtype.parent
local environment = require "environment"
lookup = environment.lookup
bind = environment.bind
local expand = require "expand"

-- TEMPORARY:
c2.asts = {}


---------------------------------------------------------------------------------------------------
-- Create parser
---------------------------------------------------------------------------------------------------

local function make_parser_from(parse_something, expected_pt_node)
   return function(src, messages)
	     assert(type(src)=="string", "src is " .. tostring(src))
	     assert(type(messages)=="table")
	     local pt, warnings, leftover = parse_something(src)
	     assert(type(warnings)=="table")
	     if not pt then
		table.insert(messages, cerror.new("syntax", {}, table.concat(warnings, "\n")))
		return false
	     end
	     table.move(warnings, 1, #warnings, #messages+1, messages)
	     assert(type(pt)=="table")
	     assert(pt.type==expected_pt_node, util.table_to_pretty_string(pt, false))
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

---------------------------------------------------------------------------------------------------
-- Syntax expander
---------------------------------------------------------------------------------------------------

c2.expand_block = expand.block
c2.expand_expression = expand.expression

---------------------------------------------------------------------------------------------------
-- Compile bindings and expressions
---------------------------------------------------------------------------------------------------

local compile_expression;

local function literal(a, pkgtable, env, messages)
   local str, offense = common.unescape_string(a.value)
   if not str then
      throw("invalid escape sequence in literal: \\" .. offense, a)
   end
   return pattern.new{name="literal"; peg=P(a.value); ast=a}
end

local function sequence(a, pkgtable, env, messages)
   assert(#a.exps > 0, "empty sequence?")
   local peg = compile_expression(a.exps[1], pkgtable, env, messages).peg
   for i = 2, #a.exps do
      peg = peg * compile_expression(a.exps[i], pkgtable, env, messages).peg
   end
   return pattern.new{name="sequence", peg=peg, ast=a}
end

local function choice(a, pkgtable, env, messages)
   assert(#a.exps > 0, "empty choice?")
   local peg = compile_expression(a.exps[1], pkgtable, env, messages).peg
   for i = 2, #a.exps do
      peg = peg + compile_expression(a.exps[i], pkgtable, env, messages).peg
   end
   return pattern.new{name="choice", peg=peg, ast=a}
end

local function predicate(a, pkgtable, env, messages)
   local peg = compile_expression(a.exp, pkgtable, env, messages).peg
   if a.type=="@" then
      peg = #peg
   elseif a.type=="!" then
      peg = (- peg)
   else
      throw("invalid predicate type: " .. tostring(a.type), a)
   end
   return pattern.new{name="predicate", peg=peg, ast=a}
end


-- TODO: Change each "1" below to lookup(env, ".")


local function cs_named(a, pkgtable, env, messages)
   local peg = locale[a.name]
   if not peg then
      throw("unknown named charset: " .. a.name, a)
   end
   -- The posix character sets are ascii-only, so the "1-peg" below is ok.
   return pattern.new{name="cs_named", peg=((a.complement and 1-peg) or peg), ast=a}
end

-- TODO: This impl works only for single byte chars!
local function cs_range(a, pkgtable, env, messages)
   local c1, offense1 = common.unescape_charlist(a.first)
   local c2, offense2 = common.unescape_charlist(a.last)
   if (not c1) or (not c2) then
      throw("invalid escape sequence in character set: \\" ..
	    (c1 and offense2) or offense1,
	 a)
   end
   local peg = R(c1..c2)
   return pattern.new{name="cs_range", peg=(complement and (1-peg)) or peg, ast=a}
end

-- FUTURE optimization: All the single-byte chars can be put into one call to lpeg.S().
-- FUTURE optimization: The multi-byte chars can be organized by common prefix. 
function cs_list(a, pkgtable, env, messages)
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
   return pattern.new{name="cs_list",
		      peg=(a.complement and (1-alternatives) or alternatives),
		      ast=a}
end

local cexp;

function cs_exp(a, pkgtable, env, messages)
   if ast.cs_exp.is(a.cexp) then
      if not a.complement then
	 -- outer cs_exp does not affect semantics, so drop it
	 return cs_exp(a.cexp)
      else
	 -- either: inner cs_exp does not affect semantics, so drop it,
	 -- or: complement of a complement cancels out.
	 local new = ast.cs_exp{complement=(not a.cexp.complement), cexp=a.cexp.cexp, s=a.s, e=e.s}
	 return cs_exp(new, pkgtable, env, messages)
      end
   elseif ast.cs_union.is(a.cexp) then
      assert(#a.cexp.cexps > 0, "empty character set union?")
      local alternatives = compile_expression(a.cexp.cexps[1]).peg
      for i = 2, #a.cexp.cexps do
	 alternatives = alternatives + compile_expression(a.cexp.cexps[i]).peg
      end
      return pattern.new{name="cs_exp",
			 peg=((a.complement and (1-alternatives)) or alternatives),
			 ast=a}
   elseif ast.cs_intersection.is(a.cexp) then
      throw("character set intersection is not implemented", a)
   elseif ast.cs_difference.is(a.cexp) then
      throw("character set difference is not implemented", a)
   elseif ast.simple_charset_p(a) then
      local p = compile_expression(a, pkgtable, env, messages)
      return pattern.new{name="cs_exp", peg=((a.complement and (1-p.peg)) or p.peg), ast=a}
   else
      assert(false, "unknown cexp inside cs_exp", a)
   end
end

-- Can't just run peg:match("") because a lookahead expression will return nil (i.e. it will not
-- match the empty string), even though it cannot be put into a loop (because it consumes no
-- input).
local function matches_empty(peg)
   local ok, msg = pcall(function() return peg^1 end)
   return (not ok) and msg:find("loop body may accept empty string")
end

local function repetition(a, pkgtable, env, messages)
   local boundary_pattern, boundary
   if a.cooked then
      boundary_pattern = lookup(env, common.boundary_identifier)
      if not pattern.is(boundary_pattern) then
	 throw("a very unusual situation occurred in which the boundary identifier, " ..
	       common.boundary_identifier, ", is not bound to a pattern", a)
      end
      boundary = boundary_pattern.peg
      assert(boundary)
   end -- if a.cooked
   local epat = compile_expression(a.exp, pkgtable, env, messages)
   local epeg = epat.peg
   if matches_empty(epeg) then
      throw("pattern being repeated can match the empty string", a)
   end
   local qpeg
   local min, max, cooked = a.min, a.max, a.cooked
   if (not min) then min = 0; end		    -- {,max}
   if (not max) then
      if min==1 then				    -- +
	 if cooked then qpeg = (epeg * boundary)^1
	 else qpeg = epeg^1; end
      elseif min==0 then			    -- *
	 if cooked then qpeg = (epeg * (boundary * epeg)^0)^-1
	 else qpeg = epeg^0; end
      else
	 assert(type(min)=="number", "min not a number? " .. tostring(min))
	 assert(min > 0)
	 if cooked then qpeg = (epeg * (boundary * epeg)^(min-1))
	 else qpeg = epeg^min; end		    -- {min,}
      end -- switch on min
   else -- have a max and a min value
      if min > max then
	 throw("invalid repetition (min must be greater than max)", a)
      elseif (max < 1) then
	 throw("invalid repetition (max must be greater than zero)", a)
      elseif min < 0 then
	 throw("invalid repetition (min must be greater than or equal to zero)", a)
      end
      -- Here's where things get interesting, because we must match at least min copies of
      -- epeg, and at most max.
      if min==0 then
	 qpeg = ((cooked and (boundary * epeg)) or epeg)^(-max)
      else
	 assert(min > 0)
	 qpeg = epeg
	 for i=1, (min-1) do
	    qpeg = qpeg * ((cooked and (boundary * epeg)) or epeg)
	 end -- for
	 if (min-max) < 0 then
	    qpeg = qpeg * ((cooked and (boundary * epeg) or epeg)^(min-max))
	 else
	    assert(min==max)
	 end
      end -- switch on min
   end
   -- return peg being quantified, quantified peg, whether boundary was appended, quantifier name, min, max
   return pattern.new{name="repetition", peg=qpeg, ast=a}
end

local function ref(a, pkgtable, env, messages)
   local pat = lookup(env, a.localname, a.packagename)
   if (not pat) then throw("unbound identifier", a); end
   if not(pattern.is(pat)) then
      local name = (a.packagename and (a.packagename .. ".") or "") .. a.localname
      throw("type mismatch: expected a pattern, but " .. name .. " is bound to " .. tostring(pat), a)
   end
   local newpat = pattern.new{name=a.localname, peg=pat.peg, alias=pat.alias, ast=pat.ast, raw=pat.raw, uncap=pat.uncap}
   if a.packagename and (not pat.alias) then
      -- Here, pat was wrapped with only a local name when its module was compiled.  We need to
      -- rewrap using the fully qualified name, because the code we are compiling now uses the
      -- fully qualified name to refer to this value.
      assert(pat.uncap)
      newpat.peg = common.match_node_wrap(pat.uncap, a.packagename .. "." .. a.localname)
   end
   return newpat
end

local dispatch = { [ast.literal] = literal,
		   [ast.sequence] = sequence,
		   [ast.choice] = choice,
		   [ast.ref] = ref,
		   [ast.cs_exp] = cs_exp,
		   [ast.cs_named] = cs_named,
		   [ast.cs_range] = cs_range,
		   [ast.cs_list] = cs_list,
		   [ast.repetition] = repetition,
		   [ast.predicate] = predicate,
		}

function compile_expression(a, pkgtable, env, messages)
   local compile = dispatch[parent(a)]
   if compile then
      return compile(a, pkgtable, env, messages)
   else
      print("not compiling " .. tostring(a))
      print("***"); table.print(a)
   end
end

function c2.compile_expression(...)
   return apply_catch(compile_expression, ...)
end

---------------------------------------------------------------------------------------------------
-- Compile block
---------------------------------------------------------------------------------------------------

-- Compile all the statements in the block.  Any imports were loaded during the syntax expansion
-- phase, in order to access macro definitions.
function c2.compile_block(a, pkgtable, pkgenv, messages)
   print("load: entering dummy compile_block, making novalue bindings")
   c2.asts[a.importpath or "nilimportpath"] = a	    -- TEMPORARY
   -- Step 1: For each lhs, bind the identifier to 'novalue'.
   -- TODO: Ensure each lhs appears only once in a.stmts.
   for _, b in ipairs(a.stmts) do
      assert(ast.binding.is(b))
      local ref = b.ref
      assert(not ref.packagename)
      if environment.lookup(pkgenv, ref.localname) then
	 print("      rebinding " .. ref.localname)
      else
	 print("      creating novalue binding for " .. ref.localname)
      end
      bind(pkgenv, ref.localname, novalue.new{exported=true, ast=b})
   end -- for
   -- Step 2: Compile the rhs (expression) for each binding.  
   -- TODO: If an exp depends on a 'novalue', return 'novalue'.
   -- TODO: Repeat step 2 until either every lhs is bound to an actual value (or error), or an
   --       entire pass through a.stmts fails to change any binding.
   for _, b in ipairs(a.stmts) do
      local ref, exp = b.ref, b.exp
      local ok, pat = c2.compile_expression(exp, pkgtable, pkgenv, messages)
      if not ok then
	 error("caught a lua error!\n" ..
	       tostring(pat).."\n"..
	       table.tostring(messages))
      end
      if pat then 
	 print("*** actually compiled: " .. ref.localname)
	 if type(pat)~="table" then
	    print("    BUT DID NOT GET A PATTERN: " .. tostring(pat))
	 end
	 if (not b.is_alias) then
	    if pat.uncap then
	       -- We must have an assignment like 'p1 = p2' where p2 is not an alias.  RPL semantics
	       -- are that p1 must capture the same as p2, but the output should be labeled p1.
	       pat.peg = common.match_node_wrap(pat.uncap, ref.localname)
	    else
	       -- The binding b is a capture, and there is no pat.uncap
	       pat.uncap = pat.peg
	       pat.peg = common.match_node_wrap(pat.peg, ref.localname)
	    end
	 end
	 pat.alias = b.is_alias
	 bind(pkgenv, ref.localname, pat)
      end
   end -- for

   -- Step 3: 

   return true
end

return c2
