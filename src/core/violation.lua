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
     src = NIL,
     ast = false;				    -- unused. here for duck typing.
     origin = NIL,
     line = NIL,
     charpos = NIL})

violation.compile = recordtype.new(
   "Compile error",
   { who = NIL,
     message = NIL, 
     ast = NIL,
     origin = NIL,
     line = NIL,
     charpos = NIL})

violation.warning = recordtype.new(
   "Warning",
   { who = NIL,
     message = NIL, 
     ast = NIL,
     origin = NIL,
     line = NIL,
     charpos = NIL})

violation.info = recordtype.new(
   "Info",
   { who = NIL,
     message = NIL, 
     ast = NIL,
     origin = NIL,
     line = NIL,
     charpos = NIL})

---------------------------------------------------------------------------------------------------
-- Formatting messages
---------------------------------------------------------------------------------------------------

function violation.tostring(err)
   local kind = recordtype.typename(err)
   if not kind then
      return "UNKNOWN ERROR OBJECT: " .. tostring(err)
   else
      local str = kind .. "\n"
      str = str .. " [" .. err.who .. "]: " .. err.message .. "\n"
      if err.ast then
	 -- TODO: use something better than the default tostring for ast objects
	 str = str .. tostring(err.ast) .. "\n"
      end
      if line then
	 str = str .. string.format("At line %d", line)
	 if charpos then
	    str = str .. string.format(", position %d", charpos)
	 end
	 if origin then
	    str = str .. " of " .. origin
	 end
	 str = str .. "\n"
      elseif origin then
	 str = str .. "In " .. origin .. "\n"
      end
   end
   return str
end

---------------------------------------------------------------------------------------------------
-- Catch / throw
---------------------------------------------------------------------------------------------------

-- 'catch' applies f to args until it returns or yields.
-- Like pcall, return a success code in front of return values.
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
