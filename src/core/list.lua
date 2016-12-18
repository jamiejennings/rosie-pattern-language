---- -*- Mode: Lua; -*-                                                                           
----
---- list.lua     Some list functions, where lists are Lua tables with consecutive integer keys
----
---- © Copyright IBM Corporation 2016.
---- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
---- AUTHOR: Jamie A. Jennings

-- This set of list functions treats Lua tables with consecutive integer keys as if they were
-- lists.  Important limitations include:
--   No support for pairs
--   The cdr implementation conses (sigh).
--   An eq function on lists isn't possible, because eq(cdr(ls), cdr(ls)) ==> false.

function to_list(tbl)
   if type(tbl)=="table" then
      return setmetatable(map(to_list, tbl), list_metatable)
   else
      return tbl
   end
end

function list_p(obj)
   if (type(obj)=="table") then
      for k,v in pairs(obj) do
	 if type(k)~="number" then return false; end
      end
      return true
   end
   return false
end

function null_p(ls)
   if list_p(ls) then return (#ls==0); end
   error("not a list: " .. tostring(ls))
end

function cons(elt, ls)
   if not list_p(ls) then error("not a list: " .. tostring(ls)); end
   return setmetatable({elt, table.unpack(ls)}, list_metatable)
end

function car(ls)
   if null_p(ls) then error("empty list"); end
   return ls[1]
end

-- this implementation of cdr breaks 'eq':
-- eq(cdr(l), cdr(l)) ==> false
function cdr(ls)
   if null_p(ls) then error("empty list"); end
   return setmetatable({ table.unpack(ls, 2) }, list_metatable)
end

function list(...)
   return setmetatable({...}, list_metatable)
end

function append(l1, ...)
   local result = list(table.unpack(l1))	    -- shallow copy
   for _, l in ipairs({...}) do
      table.move(l, 1, #l, #result+1, result)
   end
   return result
end

function and_function(a, b)
   return (a and b)
end

function or_function(a, b)
   return (a or b)
end

function equal(e1, e2)
   if type(e1)=="table" then
      if (e1==e2) then return true		    -- same table
      elseif type(e2)~="table" then return false
      else
	 return reduce(and_function, true, map(equal, e1, e2))
      end
   else
      return (e1==e2)
   end
end

function member(elt, ls)
   if null_p(ls) then return false; end
   for _, item in ipairs(ls) do
      if equal(elt, item) then return true; end
   end
   return false
end

function last(ls)
   if null_p(ls) then error("empty list"); end
   return ls[#ls]
end

function list_tostring(ls)
   if null_p(ls) then return("{}"); end
   local str, elt_str
   for _,elt in ipairs(ls) do
      elt_str = ((list_p(elt) and list_tostring(elt)) or tostring(elt))
      if str then str = str .. ", " .. elt_str
      else str = "{" .. elt_str; end
   end
   return str .. "}"
end
   
function list_print(ls)
   print(list_tostring(ls))
end

function apply(fn, ls)
   return fn(table.unpack(ls))
end

function apply_at_i(fn, i, ...)
   assert(type(i)=="number")
   local args = list()
   local lists = {...}
   for _,lst in ipairs(lists) do
      table.insert(args, lst[i])
   end
   return fn(table.unpack(args))
end

-- limitation: the fn can only return one value.
function map(fn, ls1, ...)
   local results = list()
   for i=1,#ls1 do
      results[i] = apply_at_i(fn, i, ls1, ...)
   end
   return results
end

-- limitation: the fn can only return one value.
-- limitation: only the first list's elements are present in the result.
function filter(fn, ls1, ...)
   local results = list()
   local out_index = 1
   for i=1,#ls1 do
      local temp = apply_at_i(fn, i, ls1, ...)
      if temp then
	 results[out_index] = ls1[i]
	 out_index = out_index + 1
      end
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
   if i > #lst then
      return init
   else
      return reduce(fn, fn(init, lst[i]), lst, i+1)
   end
end

function flatten(ls)
   if null_p(ls) then return ls;
   elseif list_p(car(ls)) then
      return append(flatten(car(ls)), flatten(cdr(ls)))
   else
      return cons(car(ls), flatten(cdr(ls)))
   end
end

function reverse(ls)
   if null_p(ls) then return ls;
   elseif #ls==1 then return ls;
   else return append(reverse(cdr(ls)), list(car(ls)))
   end
end

-- Metatable

list_metatable =
   { __tostring = list_tostring }

