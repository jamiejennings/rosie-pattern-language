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
local ast = import "ast"
local lpeg = import "lpeg"

function builtins.message(...)
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
   if optional_name then assert(type(optional_name.value)=="string"); end
   return lpeg.rconstcap(arg.value, optional_name and optional_name.value or "message")
end

return builtins

