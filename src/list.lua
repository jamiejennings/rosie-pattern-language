---- -*- Mode: Lua; -*-                                                                           
----
---- list.lua     Some list functions, where lists are Lua tables with consecutive integer keys
----
---- © Copyright IBM Corporation 2016.
---- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
---- AUTHOR: Jamie A. Jennings


function apply_at_i(fn, i, ...)
   assert(type(i)=="number")
   local args = {}
   local lists = {...}
   for _,lst in ipairs(lists) do
      table.insert(args, lst[i])
   end
   return fn(table.unpack(args))
end

-- limitation: the fn can only return one value.
function map(fn, ls1, ...)
   local results = {}
   for i=1,#ls1 do
      results[i] = apply_at_i(fn, i, ls1, ...)
   end
   return results
end

function foreach(fn, ls1, ...)
   for i=1,#ls1 do
      apply_at_i(fn, i, ls1, ...)
   end
end

function reduce(fn, init, lst, i)
   i = i or 1
   if not lst[i] then
      return init
   else
      return reduce(fn, fn(init, lst[i]), lst, i+1)
   end
end

