-- -*- Mode: Lua; -*-                                                                             
--
-- parse.lua (was p2)    parsing functions to support the c2 compiler
--
-- © Copyright IBM Corporation 2016, 2017.
-- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
-- AUTHOR: Jamie A. Jennings

local common = require "common"
local decode_match = common.decode_match
local util = require "util"
local parse_core = require "parse_core"

local p2 = {}

----------------------------------------------------------------------------------------
-- Syntax error reporting (this is a very basic capability, which could be much better)
----------------------------------------------------------------------------------------

local function preparse(rplx_preparse, input)
   local major, minor
   local language_decl, leftover
   if type(input)=="string" then
      language_decl, leftover = rplx_preparse:match(input)
   elseif type(input)=="table" then
      -- Assume ast provided, although it will be empty even if the original source was not, 
      -- because the source could contain only comments and/or whitespace
      if not input[1] then return nil, nil, 1; end
      if input[1].type=="language_decl" then
	 language_decl = input[1]
	 leftover = #input - language_decl.fin
      end
   else
      assert(false, "preparse called with neither string nor ast as input: " .. tostring(input))
   end
   if language_decl then
      if parse_core.syntax_error_check(language_decl) then
	 return false, "Syntax error in language version declaration: " .. language_decl.data
      else
	 major = tonumber(language_decl.subs[1].subs[1].data) -- major
	 minor = tonumber(language_decl.subs[1].subs[2].data) -- minor
	 return major, minor, #input-leftover+1
      end
   else
      return nil, nil, 1
   end
end

local function vstr(maj, min)
   return tostring(maj) .. "." .. tostring(min)
end

function p2.make_preparser(rplx_preparse, supported_version)
   local incompatible = function(major, minor, supported)
			   return (major > supported.major) or (major==supported.major and minor > supported.minor)
			end
   return function(source)
	     local major, minor, pos = preparse(rplx_preparse, source)
	     if major then
		common.note("-> Parser noted rpl version declaration ", vstr(major, minor))		
		if incompatible(major, minor, supported_version) then
		   return nil, nil, nil,
		   "Error: loading rpl that requires version " .. vstr(major, minor) ..
		   " but engine is at version " .. vstr(supported_version.major, supported_version.minor)
	        end
		if major < supported_version.major then
		   common.warn("loading rpl source at version " ..
			vstr(major, minor) .. 
		     " into engine at version " ..
		     vstr(supported_version.major, supported_version.minor))
		end
		return major, minor, pos
	     else
		common.note("-> Parser saw no rpl version declaration")
		return 0, 0, 1
	     end -- if major
	  end -- preparser function
end -- make_preparser

---------------------------------------------------------------------------------------------------
-- Parse block
---------------------------------------------------------------------------------------------------

local function collect_syntax_error_nodes(pt, syntax_errors)
   -- Find all the syntax error nodes in the parse tree, and make a list of their parents.  The
   -- root is handled by the caller.
   for _,a in ipairs(pt.subs or {}) do
      if a.type=="syntax_error" then
	 table.insert(syntax_errors, pt)
      else
	 collect_syntax_error_nodes(a, syntax_errors)
      end
   end
   return syntax_errors
end

local function find_syntax_errors(pt, source)
   if pt.type=="syntax_error" then
      return {pt}
   else
      return collect_syntax_error_nodes(pt, {})
   end
end

-- 'parse_block' returns: parse tree, syntax error list, leftover chars
-- The caller must check whether the parse is successful by examining the error list (which should
-- be empty) and the leftover value (which should be 0).
function p2.make_parse_block(rplx_preparse, rplx_statements, supported_version)
   -- The preparser function uses rplx_preparse to look for a rpl language version declaration,
   -- and, if found, ensures that it is compatible with supported_version.
   local preparser = p2.make_preparser(rplx_preparse, supported_version)
   return function(src)
	     assert(type(src)=="string",
		    "Error: source argument is not a string: "..tostring(src) ..
		    "\n" .. debug.traceback())
	     local maj, min, start, err = preparser(src)
	     if not maj then return nil, {err}, 0; end
	     -- Input is compatible with what is supported, so we continue parsing
	     local pt, leftover = rplx_statements:match(src, start)
	     local syntax_errors = find_syntax_errors(pt, src)
	     -- FUTURE: If successful, we could do a 'lint' pass to produce warnings, and return
	     -- them in place of the empty error list in the return values.
	     return pt, syntax_errors, leftover
	  end -- parse_block
end -- make_parse_block

function p2.make_parse_expression(rplx_expression)
   return function(src)
	     assert(type(src)=="string",
		    "Error: source argument is not a string: "..tostring(src) ..
		    "\n" .. debug.traceback())
	     local pt, leftover = rplx_expression:match(src)
	     local syntax_errors = find_syntax_errors(pt, src)
	     return pt, syntax_errors, leftover
	  end -- parse_expression
end -- make_parse_expression


return p2
