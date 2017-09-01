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
local thread = require "thread"

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
     ast = NIL,					    -- really: an ast or a sourceref (a common.source record)
  })

violation.warning = recordtype.new(
   "Warning",
   { who = NIL,
     message = NIL, 
     ast = NIL,					    -- really: an ast or a sourceref (a common.source record)
  })

violation.info = recordtype.new(
   "Info",
   { who = NIL,
     message = NIL, 
     ast = NIL,					    -- really: an ast or a sourceref (a common.source record)
  })

---------------------------------------------------------------------------------------------------
-- Formatting messages
---------------------------------------------------------------------------------------------------

function origin_tostring(sref)
   local s, e = sref.s, sref.e
   local origin = sref.origin
   assert(origin==nil or common.loadrequest.is(origin),
	  "origin is neither nil nor a loadrequest: " .. tostring(origin))
   local filename = "user input "
   if origin then
      if origin.filename then
	 filename = origin.filename
      else
	 return "while trying to import " .. assert(origin.importpath)
      end
   end
   assert(filename, "origin has neither importpath nor filename set")
   local str = "in " .. filename
   if s then
      local source_line, line_pos, line_no = util.extract_source_line_from_pos(sref.text, s)
      str = str .. ":" .. tostring(line_no) .. ":" .. tostring(line_pos) .. ": "
      str = str .. util.trim(source_line)
   end
   return str
end

function violation.sourceref_tostring(sref)
   local str
   while sref do
      if (not sref.origin) or sref.origin.filename then
	 local new = origin_tostring(sref)
	 if not str then str = new
	 else str = str .. "\n\t" .. new; end
      end
      sref = sref.parent
   end -- while
   return str or ""
end

local function indent(str)
   return str:gsub('\n', '\n\t')
end

function violation.tostring(err)
   local kind = recordtype.typename(err)
   if not kind then
      return "Unexpected error type: " .. tostring(err)
   end
   local str = kind .. "\n"
   str = str .. "\t[" .. err.who .. "]: " .. indent(err.message) .. "\n\t"
   if violation.syntax.is(err) then
      local sref = assert(err.sourceref)
      return str .. violation.sourceref_tostring(sref)
   else
      -- Except for syntax errors, other violations have an associated ast
      local a = err.ast
      if not a then
	 local details = {}
	 for k,v in pairs(err) do
	    table.insert(details, tostring(k) .. ": " .. tostring(v))
	 end
	 assert(false, "violation record does not have an ast/sourceref field: " ..
		table.concat(details, "\n"))
      end
      -- And that ast is sometimes a loadrequest, when the violation occurred directly from a
      -- request to load code, e.g. from loadpkg.source().
      local sref
      if common.source.is(a) then
	 sref = a
      else
	 sref = assert(a.sourceref, tostring(a) .. " does not have a sourceref!")
      end
      return str .. violation.sourceref_tostring(sref)
   end -- if syntax error or other kind
end

---------------------------------------------------------------------------------------------------
-- Catch / throw
---------------------------------------------------------------------------------------------------

-- 'catch' applies f to args until it returns or yields.
-- Like pcall, return a success code in front of return values, and when that code is false, there
-- was a lua error.  First return value should be checked with thread.exception.is().
violation.catch = thread.pcall
violation.raise = thread.raise
violation.is_exception = thread.exception.is
violation.throw_value = thread.throw

return violation
