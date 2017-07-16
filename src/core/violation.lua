-- -*- Mode: Lua; -*-                                                                             
--
-- violation.lua   Functions for creating, signaling, and printing errors
--
-- © Copyright IBM Corporation 2017.
-- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
-- AUTHOR: Jamie A. Jennings

local violation = {}

local recordtype = require "recordtype"
local NIL = recordtype.NIL

----------------------------------------------------------------------------------------
-- Error type
----------------------------------------------------------------------------------------

violation.syntax = recordtype.new(
   "Syntax error",
   { who = NIL,
     message = NIL, 
     sourceref = NIL,
  })

violation.compile = recordtype.new(
   "Compile error",
   { who = NIL,
     message = NIL, 
     ast = NIL,
  })

violation.warning = recordtype.new(
   "Warning",
   { who = NIL,
     message = NIL, 
     ast = NIL,
  })

violation.info = recordtype.new(
   "Info",
   { who = NIL,
     message = NIL, 
     ast = NIL,
  })

---------------------------------------------------------------------------------------------------
-- Formatting messages
---------------------------------------------------------------------------------------------------

function violation.loadrequest_tostring(origin)
   if not origin then return "in user input "; end
   assert(ast.loadrequest.is(origin), "origin is neither nil nor a loadrequest: " .. tostring(origin))
   local origin_desc
   if origin.importpath then
      origin_desc = "while trying to import " .. origin.importpath
   elseif origin.filename then
      assert(type(origin.filename)=="string")
      origin_desc = "while trying to load " .. origin.filename
   else
      assert(false, "origin has neither importpath nor filename set")
   end
   return origin_desc .. "\n " .. violation.loadrequest_tostring(origin.parent)
end

function violation.sourceref_tostring(sref)
   local s, e = sref.s or 1, sref.e or #sref.text
   local origin_desc = violation.loadrequest_tostring(sref.origin)
   assert(type(sref.text)=="string")
   local source_line, line_pos, line_no = util.extract_source_line_from_pos(sref.text, s)
   local str = ""
--   str = str .. "\n"
   str = str .. tostring(origin_desc)
   str = str .. ":" .. tostring(line_no) .. ":" .. tostring(line_pos) .. ": "
   str = str .. source_line
   if sref.origin and sref.origin.parent then
      return str .. "\n" .. violation.loadrequest_tostring(sref.origin.parent)
   else
      return str
   end
end

function violation.tostring(err)
   local kind = recordtype.typename(err)
   if not kind then
      return "Unexpected error type: " .. tostring(err)
   end
   local str = kind .. "\n"
   str = str .. " [" .. err.who .. "]: " .. err.message .. "\n "
   if violation.syntax.is(err) then
      local sref = assert(err.sourceref)
      return str .. violation.sourceref_tostring(sref)
   else
      -- Except for syntax errors, other violations have an associated ast
      local a = assert(err.ast, util.table_to_pretty_string(err, false))
      -- And that ast is sometimes a loadrequest, when the violation occurred directly from a
      -- request to load code, e.g. from loadpkg.source().
      if ast.loadrequest.is(a) then
	 return str .. violation.loadrequest_tostring(a)
      else
	 local sref = assert(a.sourceref, tostring(a) .. " does not have a sourceref!")
	 -- TODO: use something better than the default tostring for ast objects?
--	 str = str .. " " .. ast.tostring(a)
	 return str .. violation.sourceref_tostring(sref)
      end
   end -- if syntax error or other kind
end

---------------------------------------------------------------------------------------------------
-- Catch / throw
---------------------------------------------------------------------------------------------------

-- 'catch' applies f to args until it returns or yields.
-- Like pcall, return a success code in front of return values, and when that code is false, there
-- was a lua error.
function violation.catch(f, ...)
   local t = coroutine.create(f)
   return coroutine.resume(t, ...)
end

function violation.throw(violation_object)
   if coroutine.isyieldable() then
      coroutine.yield(false, violation_object)
   else
      error("Uncaught violation:\n", violation.tostring(violation_object), 2)
   end
end

return violation
