-- -*- Mode: Lua; -*-                                                                             
--
-- c2.lua   RPL 1.1 compiler
--
-- © Copyright Jamie A. Jennings 2017.
-- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
-- AUTHOR: Jamie A. Jennings


local c2 = {}

c2.parse_block = function(...)
		      print("load: dummy parse_block called")
		      return true
		   end

c2.compile_block = function(...)
		      print("load: dummy compile_block called")
		      return true
		   end

c2.expand_block = function(a, env, messages)
   -- ... TODO ...
   print("load: dummy expand_block function called")
   return true
end

return c2
