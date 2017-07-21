-- -*- Mode: Lua; -*-                                                                             
--
-- builtins.lua
--
-- © Copyright IBM Corporation 2017.
-- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
-- AUTHOR: Jamie A. Jennings

local builtins = {}

local ast = import "ast"


function builtins.message(...)
   local args = {...}
   if #args~=1 then error("macro takes one argument, " .. tostring(#args) .. " given"); end
   local exp = args[1]
   local sref = assert(exp.sourceref)
   if not ast.literal.is(exp) then error('message macro takes a string argument'); end
   assert(type(exp.value)=="string")
   return ast.message.new{value=exp.value, sourceref=sref}
end

return {}
