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
   if #args~=1 then
      error("function takes one argument, " .. tostring(#args) .. " given")
   end
   local arg = args[1]
   if common.taggedvalue.is(arg) and (arg.type=="string" or arg.type=="hashtag") then
      assert(type(arg.value)=="string")
      return lpeg.rconstcap(arg.value, "message")
   else
      error("function takes a string argument, " .. type(msg) .. " given")
   end
end

return builtins

