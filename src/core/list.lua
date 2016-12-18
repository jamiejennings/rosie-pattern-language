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

-- Some functions are designed to operate on the consecutively numbered entries in any table.
-- I.e. the table does NOT have to be a proper list.  

local list = {}

local list_metatable =
   { __tostring = list.list_tostring }

function list.from_table(tbl)
   if type(tbl)=="table" then
      if list.validate_structure(tbl) then
	 return setmetatable(tbl, list_metatable)
      else
	 error("arg to from_table cannot be coerced to a list (gaps or non-numeric indices present)")
      end
   end
   error("not a table: " .. tostring(tbl))
end

function list.is(obj)				    -- in scheme: list?
   return (getmetatable(obj)==list_metatable)
end

function list.validate_structure(obj)
   if (type(obj)~="table") then return false; end
   local len = 0
   -- Only numeric indices in our lists
   for k,v in pairs(obj) do
      if type(k)~="number" then return false; end
      len = (k > len) and k or len
   end
   -- No gaps in the numbers
   for i=1,len do
      if not obj[len] then return false; end	    -- a gap
   end
   return true
end

function list.is_null(ls)			    -- in scheme: null?
   --if list.is(ls) then return (#ls==0); end
   if type(ls)=="table" then return (#ls==0); end
   error("not a list: " .. tostring(ls))
end

function list.cons(elt, ls)
   --if list.is(ls) then
   if type(ls)=="table" then
      return setmetatable({elt, table.unpack(ls)}, list_metatable)
   end
   error("not a list: " .. tostring(ls))
end

function list.car(ls)
   if list.is_null(ls) then error("empty list"); end
   return ls[1]
end

-- this implementation of cdr breaks 'eq':
-- eq(cdr(l), cdr(l)) ==> false
function list.cdr(ls)
   if list.is_null(ls) then error("empty list"); end
   return setmetatable({ table.unpack(ls, 2) }, list_metatable)
end

function list.new(...)				    -- ugh. looks like OO.
   return setmetatable({...}, list_metatable)
end

function list.append(l1, ...)
   local result = list.new(table.unpack(l1))	    -- shallow copy
   for _, l in ipairs({...}) do
      table.move(l, 1, #l, #result+1, result)
   end
   return result
end

function list.andf(a, b)
   return (a and b)
end

function list.orf(a, b)
   return (a or b)
end

function list.equal(e1, e2)
   if list.is(e1) then
      if (e1==e2) then return true		    -- same table
      elseif not list.is(e2) then return false
      else
	 return list.reduce(list.andf, true, list.map(list.equal, e1, e2))
      end
   else
      return (e1==e2)
   end
end

function list.member(elt, ls)
   if list.is_null(ls) then return false; end
   for _, item in ipairs(ls) do
      if list.equal(elt, item) then return true; end
   end
   return false
end

function list.last(ls)
   if list.is_null(ls) then error("empty list"); end
   return ls[#ls]
end

function list.tostring(ls)
   if list.is_null(ls) then return("{}"); end
   local str, elt_str
   for _,elt in ipairs(ls) do
      elt_str = ((list.is(elt) and list.tostring(elt)) or tostring(elt))
      if str then str = str .. ", " .. elt_str
      else str = "{" .. elt_str; end
   end
   return str .. "}"
end
   
function list.print(ls)
   print(list.tostring(ls))
end

function list.apply(fn, ls)
   return fn(table.unpack(ls))
end

function list.apply_at_i(fn, i, ...)
   assert(type(i)=="number")
   local args = list.new()
   local lists = {...}
   for _,lst in ipairs(lists) do
      table.insert(args, lst[i])
   end
   return fn(table.unpack(args))
end

-- limitation: the fn can only return one value.
function list.map(fn, ls1, ...)
   local results = list.new()
   for i=1,#ls1 do
      results[i] = list.apply_at_i(fn, i, ls1, ...)
   end
   return results
end

-- limitation: the fn can only return one value.
-- limitation: only the first list's elements are present in the result.
function list.filter(fn, ls1, ...)
   local results = list.new()
   local out_index = 1
   for i=1,#ls1 do
      local temp = list.apply_at_i(fn, i, ls1, ...)
      if temp then
	 results[out_index] = ls1[i]
	 out_index = out_index + 1
      end
   end
   return results
end

function list.foreach(fn, ls1, ...)
   for i=1,#ls1 do
      list.apply_at_i(fn, i, ls1, ...)
   end
end

function reduce(fn, init, lst, i)
   i = i or 1
   if i > #lst then
      return init
   else
      return list.reduce(fn, fn(init, lst[i]), lst, i+1)
   end
end

function list.flatten(ls)
   if list.is_null(ls) then return ls;
   elseif list.is(list.car(ls)) then
      return list.append(list.flatten(list.car(ls)), list.flatten(list.cdr(ls)))
   else
      return list.cons(list.car(ls), list.flatten(list.cdr(ls)))
   end
end

function list.reverse(ls)
   if list.is_null(ls) then return ls;
   elseif #ls==1 then return ls;
   else return list.append(list.reverse(list.cdr(ls)), list(list.car(ls)))
   end
end

return list
