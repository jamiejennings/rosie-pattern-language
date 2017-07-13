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

function violation.sourceref_tostring(sref)
   local s, e = sref.s or 1, sref.e or #sref.source
   local origin = "user input "
   if ast.importrequest.is(sref.origin) then
      origin = "package " .. sref.origin.importpath
   end
   assert(type(sref.source)=="string")
   local str = ""
   local source_line, line_pos, line_no = util.extract_source_line_from_pos(sref.source, s)
   str = str .. "\n"
   str = str .. " In " .. tostring(origin)
   str = str .. ":" .. tostring(line_no) .. ":" .. tostring(line_pos) .. ": "
   str = str .. source_line
   return str
end

function violation.tostring(err)
   local kind = recordtype.typename(err)
   if not kind then
      return "UNKNOWN ERROR OBJECT: " .. tostring(err)
   end
   local str = kind .. "\n"
   str = str .. " [" .. err.who .. "]: " .. err.message
   if violation.syntax.is(err) then
      local sref = assert(err.sourceref)
      return str .. violation.sourceref_tostring(sref)
   else
      local a = assert(err.ast)
      local items = {"'" .. ast.tostring(a) .. "' did not have a sourceref!"}
      for k,v in pairs(a) do
	 table.insert(items, "a." .. k .. " = " .. tostring(v))
      end

      local sref = assert(a.sourceref, table.concat(items, "\n"))
		       
      -- TODO: use something better than the default tostring for ast objects?
      str = str .. " " .. ast.tostring(a)
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
