-- -*- Mode: Lua; -*-                                                                             
--
-- builtins.lua
--
-- © Copyright IBM Corporation 2017.
-- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
-- AUTHOR: Jamie A. Jennings

local builtins = {}

local common = import "common"
local pattern = common.pattern
local macro = common.macro
local pfunction = common.pfunction
local ast = import "ast"
local lpeg = import "lpeg"

local locale = common.locale

local boundary_ref = ast.ref.new{localname=common.boundary_identifier,
				 sourceref=
				    common.source.new{s=1, e=1,
						      origin=common.loadrequest.new{importpath="<built-ins>"},
						      text=common.boundary_identifier}}

local function internal_macro_find1(capture_flag, ...)
    -- grammar
    --    alias find = {search <exp>}  OR  {search { ~ <exp> ~}}
    --    alias search = {!<exp> .}*
    -- end
   assert(type(capture_flag)=="boolean")
   local args = {...}
   if #args~=1 then error("find takes one argument, " .. tostring(#args) .. " given"); end
   local original_exp = args[1]
   local sref = original_exp.sourceref
   assert(sref)
   local exp
   if ast.cooked.is(original_exp) then
      exp = ast.cooked.new{exp = ast.sequence.new{exps={boundary_ref, original_exp.exp, boundary_ref},
					       sourceref=sref},
			sourceref=sref}
   else
      exp = original_exp
   end
   local any_char = ast.ref.new{localname=".", sourceref=sref}
   local not_exp = ast.predicate.new{type="negation", exp=exp, sourceref=sref}
   local search_exp =
      ast.repetition.new{min=0,
			 exp=ast.raw.new{exp=ast.sequence.new{exps={not_exp, any_char},
							      sourceref=sref},
				         sourceref=sref},
		         sourceref=sref}
   local search_ref = ast.ref.new{localname="<search>", sourceref=sref}
   local search_rule =
      ast.binding.new{ref=search_ref,
		      exp=search_exp,
		      is_alias=(not capture_flag),
		      sourceref=sref}
   local capture_rule, capture_ref
   if ( ast.ref.is(exp) or
        (ast.cooked.is(exp) and ast.ref.is(exp.exp)) or
        (ast.raw.is(exp) and ast.ref.is(exp.exp)) ) then
      capture_ref = exp
   else
      capture_ref = ast.ref.new{localname="*", sourceref=sref}
      capture_rule = ast.binding.new{ref=capture_ref,
				     -- We wrap exp in a sequence so that the sequence is named
				     -- "*", and exp keeps its name.
				     exp=ast.sequence.new{exps={exp}, sourceref=sref},
				     sourceref=sref}
   end
   local start_rule =
      ast.binding.new{ref=ast.ref.new{localname="find", sourceref=sref},
		      exp=ast.raw.new{exp=ast.sequence.new{exps={search_ref, capture_ref}, 
							   sourceref=sref},
				      sourceref=sref},
		      is_alias=true,
		      sourceref=sref}
   -- Wrapping result in a sequence because currently (commit ed9524) grammars are not being
   -- labeled in the way that other constructs are.  This is due to the fact that grammars are
   -- wrapped, i.e. labeled, during the grammar EXPRESSION compilation, whereas every other
   -- binding is wrapped in the compile_block that calls compile_expression.
   -- FUTURE: Change this (above).
   return ast.sequence.new{exps={ast.grammar.new{public_rules={start_rule},
						 private_rules={search_rule, capture_rule},
						 sourceref=sref}},
			   sourceref=sref}
end

local function macro_find(...)
   return internal_macro_find1(false, ...)		    -- do not capture the text before the match
end

local function macro_keepto(...)
   return internal_macro_find1(true, ...)		    -- capture the text before the match
end

-- grep
local function macro_findall(...)
   local args = {...}
   if #args~=1 then error("findall takes one argument, " .. tostring(#args) .. " given"); end
   local exp = args[1]
   assert(exp.sourceref)
   local find = macro_find(exp)
   assert(find.sourceref)
   return ast.repetition.new{min=1, exp=find, cooked=false, sourceref=exp.sourceref}
end

-- TODO: rewrite this with utf8 support (without relying on every literal being valid utf8)
local function macro_case_insensitive(...)
   local args = {...}
   if #args~=1 then error("ci takes one argument, " .. tostring(#args) .. " given"); end
   local exp = args[1]
   local function xform_literal(exp)
      local lc, uc = string.lower(exp.value), string.upper(exp.value)
      local chars = list.new()
      for i = 1, #exp.value do
	 local upper_lower_choices =
	    { ast.literal.new{value=uc:sub(i,i), sourceref=exp.sourceref},
	      ast.literal.new{value=lc:sub(i,i), sourceref=exp.sourceref} }
	 table.insert(chars, ast.choice.new{exps=upper_lower_choices, sourceref=exp.sourceref})
      end
      return ast.raw.new{exp=ast.sequence.new{exps=chars, sourceref=exp.sourceref}, sourceref=exp.sourceref}
   end
   return ast.visit_expressions(exp, ast.literal.is, xform_literal)
end

----------------------------------------------------------------------------------------
-- Boundary for tokenization... this is going to be customizable, but hard-coded for now
----------------------------------------------------------------------------------------

  -- - Define ~ as: s+ / b / pb / sb / $ / ^
  --   where
  --     ^ is lpeg.B(-1) -- at start of input
  --     $ is lpeg.P(-1) -- at end of input
  --     b is start/end of word as above
  --     pb is "punctuation boundary" {>[:punct:] / <[:punct:]}
  --     sb is "space boundary" {!<s >s} / {<s !>s}

local sol_peg = - lpeg.B(1)
local eol_peg = lpeg.P(-1)
-- ASCII only definitions:
local s_peg = locale.space
local w_peg = lpeg.R"AZ" + lpeg.R"az" + lpeg.R"09"
local b_peg = #w_peg - lpeg.B(w_peg)
local pb_peg = #locale.punct + lpeg.B(locale.punct)
local sb_peg = (lpeg.B(s_peg) - #s_peg) --+ (#s_peg - lpeg.B(s_peg))

local boundary = ( s_peg^1
		   + b_peg
		   + pb_peg
		   + sb_peg
		   + eol_peg
		   + sol_peg )

local utf8_char_peg = common.utf8_char_peg
	   
local b_id = common.boundary_identifier
local dot_id = common.any_char_identifier
local eol_id = common.end_of_input_identifier
local sol_id = common.start_of_input_identifier
--local halt_id = common.halt_pattern_identifier

-- -----------------------------------------------------------------------------
-- Message, error, and halt
-- -----------------------------------------------------------------------------

local function check_message_args(...)
   local args = {...}
   if #args~=1 and #args~=2 then
      error("function takes one or two arguments: " .. tostring(#args) .. " given")
   end
   local arg = args[1]
   local optional_name = args[2]
   if not (common.taggedvalue.is(arg) and (arg.type=="string" or arg.type=="hashtag")) then
      error("first argument to function not a string or tag: " .. tostring(arg))
   elseif (optional_name and
	   not (common.taggedvalue.is(optional_name) and optional_name.type=="hashtag")) then
      local thing = tostring(optional_name)
      if common.taggedvalue.is(optional_name) then
	 thing = thing .. ", holding a " .. tostring(optional_name.type) .. " value"
      end
      error("second argument to function not a tag: " .. thing)
   end
   assert(type(arg.value)=="string")
   if optional_name and #optional_name.value==0 then
      error("second argument cannot be a null string")
   end
   if optional_name then assert(type(optional_name.value)=="string"); end
   return arg.value, optional_name and optional_name.value
end

local function message_peg(...)
   local message_text, message_typename = check_message_args(...)
   return lpeg.rconstcap(message_text, message_typename or "message")
end

local function error_peg(...)
   local message_text, message_typename = check_message_args(...)
   return lpeg.rconstcap(message_text, message_typename or "error") * lpeg.Halt()
end

-- -----------------------------------------------------------------------------
-- Standard prelude, reified as the store of an environment
-- -----------------------------------------------------------------------------

local DIRECTORY = "builtin/"
local PRELUDE_NAME = "prelude"
builtins.PRELUDE_IMPORTPATH = DIRECTORY .. PRELUDE_NAME

local builtin_loadrequest = common.loadrequest.new{importpath=builtins.PRELUDE_IMPORTPATH}

builtins.sourceref = common.source.new{s=0, e=0,
				       origin=builtin_loadrequest,
				       text="",
				       parent=nil}

local prelude_entries = {
   {dot_id, pattern, utf8_char_peg, true},
   {eol_id, pattern, lpeg.P(-1), true},
   {sol_id, pattern, -lpeg.B(1), true},		    -- start of input
   {b_id, pattern, boundary, true},		    -- token boundary
   {"message", pfunction, message_peg},
   {"error", pfunction, error_peg},
   {"keepto", macro, macro_keepto},
   {"find", macro, macro_find},
   {"findall", macro, macro_findall},
   {"ci", macro, macro_case_insensitive},
}

local prelude_metatable =
   {__tostring = function(env)
		    return "<standard prelude environment>"
		 end;
    __newindex = function(env, key, value)
		    error('Compiler: prelude environment is read-only, '
			  .. 'cannot assign "' .. key .. '"')
		 end;
 }

function builtins.make_standard_prelude_store()
   local ENV = {}
   for _, e in ipairs(prelude_entries) do
      if e[2]==pattern then
	 pat = e[2].new{name=e[1]; peg=e[3]; alias=e[4]}
      elseif e[2]==pfunction then
	 pat = e[2].new{primop=e[3]}
      elseif e[2]==macro then
	 pat = e[2].new{primop=e[3]}
      else
	 error("error initializing standard prelude")
      end
      local a = ast.ref.new{localname=e[1],
			    sourceref=builtins.sourceref,
			    pat=pat}
      pat.ast = a
      ENV[e[1]] = pat
   end -- for
   setmetatable(ENV, prelude_metatable)
   return ENV
end
      
-- All the builtin packages:
local BUILTINS = {
   [builtins.PRELUDE_IMPORTPATH] = {pkgname=PRELUDE_NAME, store=builtins.make_standard_prelude_store()},
}

-- -----------------------------------------------------------------------------
-- Utilities
-- -----------------------------------------------------------------------------

function builtins.is_builtin_package(importpath, fullpath)
   -- If the importpath does not start with "builtin/", then false.
   -- Did we find the file (using the engine's searchpath) in the rosie standard library?
   -- If yes, then true (this is a builtin package), otherwise false.
   assert(type(importpath)=="string")
   assert(type(fullpath)=="string")
   assert(type(ROSIE_LIBDIR)=="string")
   if importpath:sub(1,#DIRECTORY) ~= DIRECTORY then return false; end
   if fullpath:sub(1,#ROSIE_LIBDIR) ~= ROSIE_LIBDIR then return false; end
   return true
end

function builtins.get_package_store(importpath)
   local probe = BUILTINS[importpath]
   if probe then
      assert(type(probe.pkgname)=="string", "built-in package name not a string?")
      assert(type(probe.store)=="table", "built-in package store not a table?")
      assert(next(probe.store), "built-in package store is empty!")
      return probe.pkgname, probe.store
   end
   return false
end

return builtins

