-- -*- Mode: Lua; -*-                                                                             
--
-- c2.lua   RPL 1.1 compiler
--
-- © Copyright Jamie A. Jennings 2017.
-- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
-- AUTHOR: Jamie A. Jennings


local c2 = {}

local lpeg = require "lpeg"
local locale = lpeg.locale()
local P, V, C, S, R, Cmt, B =
   lpeg.P, lpeg.V, lpeg.C, lpeg.S, lpeg.R, lpeg.Cmt, lpeg.B

local common = require "common"
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
c2.parses = {}
c2.asts = {}


-- TODO: the hof with the engine parameter is TEMPORARY
function c2.make_parse_block(e)
   return function(src)
	     --print("load: entering parse_block")
	     local maj, min, start = e.compiler.parser.preparse(src)
	     if not maj then error("preparse failed"); end
	     local ok, pt, leftover = e:match("rpl_statements", src, start)
	     -- TODO: syntax error check

	     c2.parses[src] = pt		    -- TEMPORARY
	     return pt, {}, leftover		    -- no warnings for now
	  end
end

c2.expand_block = expand.block

---------------------------------------------------------------------------------------------------
-- Compile bindings and expressions
---------------------------------------------------------------------------------------------------

local function literal(a, pkgtable, env, messages)
   local str, offense = common.unescape_string(a.value)
   if not str then
      throw("invalid escape sequence in literal: \\" .. offense, a)
   end
   return pattern.new{name="literal"; peg=P(a.value); ast=a}
end

local function sequence(a, pkgtable, env, messages)
   assert(#a.exps > 0, "empty sequence?")
   local peg = c2.compile_expression(a.exps[1], pkgtable, env, messages)
   for i = 2, #a.exps do
      peg = peg * c2.compile_expression(a.exps[i], pkgtable, env, messages)
   end
   return pattern.new{name="sequence", peg=peg, ast=a}
end

local function choice(a, pkgtable, env, messages)
   assert(#a.exps > 0, "empty choice?")
   local peg = c2.compile_expression(a.exps[1], pkgtable, env, messages)
   for i = 2, #a.exps do
      peg = peg + c2.compile_expression(a.exps[i], pkgtable, env, messages)
   end
   return pattern.new{name="choice", peg=peg, ast=a}
end

local function cs_named(a, pkgtable, env, messages)
   local pat = locale[a.name]
   if not pat then
      throw("unknown named charset: " .. a.name, a)
   end
   return pattern.new{name="cs_named", peg=((a.complement and 1-pat) or pat), ast=a}
end

local function cs_range(a, pkgtable, env, messages)
   local c1, offense1 = common.unescape_charlist(a.first)
   local c2, offense2 = common.unescape_charlist(a.last)
   if not c1 then
      throw("invalid escape sequence in character set: \\" .. offense, a)
   elseif not c2 then
      throw("invalid escape sequence in character set: \\" .. offense, a)
   end
   local peg = R(c1..c2)
   return pattern.new{name="cs_range", peg=(complement and (1-peg)) or peg, ast=a}
end

function cs_list(a, pkgtable, env, messages)
   assert(#a.chars > 0, "empty character set list?")
   local exps = "";
   for i, c in ipairs(a.chars) do
      local char, offense = common.unescape_charlist(c)
      -- TODO: Convert to choice so that multi-byte characters are automatically ok
      if not char then
	 throw("invalid escape sequence in character set: \\" .. offense, a)
      end
      exps = exps .. char
   end -- for
   return pattern.new{name="cs_list", peg=((a.complement and (1-S(exps))) or S(exps)), ast=a}
end

function cs_exp(a, pkgtable, env, messages)

   --   !@# LEFT OFF HERE
   --
   --   Need to process the cs_list and the cs_union as a set of choices
   -- 


end


local function ref(a, pkgtable, env, messages)
   return pattern.new{name="TEMPORARY", peg=P(1), ast=a}
end


local dispatch = { [ast.literal] = literal,
		   [ast.sequence] = sequence,
		   [ast.choice] = choice,
		   [ast.ref] = ref,
		   [ast.cs_exp] = cs_exp,
		   [ast.cs_named] = cs_named,
		   [ast.cs_range] = cs_range,
		   [ast.cs_list] = cs_list,
		}

function c2.compile_expression(a, pkgtable, env, messages)
   local compile = dispatch[parent(a)]
   if compile then
      return compile(a, pkgtable, env, messages)
   else
      print("not compiling " .. tostring(a))
   end
end


---------------------------------------------------------------------------------------------------
-- Compile block
---------------------------------------------------------------------------------------------------

-- Compile all the statements in the block.  Any imports were loaded during the syntax expansion
-- phase, in order to access macro definitions.
function c2.compile_block(a, pkgtable, pkgenv, messages)
   print("load: entering dummy compile_block, making novalue bindings")
   c2.asts[a.importpath or "nilimportpath"] = a	    -- TEMPORARY

   for _, b in ipairs(a.stmts) do
      assert(ast.binding.is(b))
      local ref = b.ref
      assert(not ref.packagename)
      if environment.lookup(pkgenv, ref.localname) then
	 print("      rebinding " .. ref.localname)
      else
	 print("      creating novalue binding for " .. ref.localname)
      end
      environment.bind(pkgenv,
		       ref.localname,
		       novalue.new{exported=true, ast=b})
   end -- for

   for _, b in ipairs(a.stmts) do
      local ref, exp = b.ref, b.exp
      local pat = c2.compile_expression(exp, pkgtable, pkgenv, messages)
      if pat then 
	 print("*** actually compiled: " .. ref.localname)
	 -- TODO: set alias flag
	 -- TODO: wrap with capture when not an alias
	 bind(pkgenv, ref.localname, pat)
      end
   end -- for

   return true
end

return c2
