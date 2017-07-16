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

function origin_tostring(sref)
   local s, e = sref.s or 1, sref.e or #sref.text
   local origin = sref.origin
   assert(origin==nil or common.loadrequest.is(origin),
	  "origin is neither nil nor a loadrequest: " .. tostring(origin))
   if origin and origin.importpath then
      return "while trying to import " .. origin.importpath
   else
      local filename = "user input "
      if origin then filename = origin.filename; end
      assert(filename, "origin has neither importpath nor filename set")      
      local str = "in " .. filename
      local source_line, line_pos, line_no = util.extract_source_line_from_pos(sref.text, s)
      str = str .. ":" .. tostring(line_no) .. ":" .. tostring(line_pos) .. ": "
      str = str .. util.trim(source_line)
      return str
   end
end

function violation.sourceref_tostring(sref)
   local str = origin_tostring(sref)
   if sref.parent then
      return str .. "\n\t" .. violation.sourceref_tostring(sref.parent)
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
   str = str .. "\t[" .. err.who .. "]: " .. err.message .. "\n\t"
   if violation.syntax.is(err) then
      local sref = assert(err.sourceref)
      return str .. violation.sourceref_tostring(sref)
   else
      -- Except for syntax errors, other violations have an associated ast
      local a = assert(err.ast, util.table_to_pretty_string(err, false))
      -- And that ast is sometimes a loadrequest, when the violation occurred directly from a
      -- request to load code, e.g. from loadpkg.source().
      local sref
      if common.source.is(a) then
	 sref = a
      else
	 sref = assert(a.sourceref, tostring(a) .. " does not have a sourceref!")
	 -- TODO: use something better than the default tostring for ast objects?
	 --	 str = str .. " " .. ast.tostring(a)
      end
      return str .. violation.sourceref_tostring(sref)
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
