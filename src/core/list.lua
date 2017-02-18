---- -*- Mode: Lua; -*-                                                                           
----
---- list.lua     Some list functions, where lists are based on Lua tables
----
---- © Copyright IBM Corporation 2016, 2017.
---- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
---- AUTHOR: Jamie A. Jennings

-- A list is a Lua table that has the list_metatable.  List functions operate on consecutive
-- integer keys of the underlying table, ignoring all other keys.
--
-- Important limitations include:
--   No support for pairs
--   The cdr implementation conses (sigh).
--   An eq function on lists isn't possible, because eq(cdr(ls), cdr(ls)) ==> false.

local list = {}

local list_metatable = {}

-- Make a new list using all of the arguments as elements (ugh! 'new' looks like OO.)
function list.new(...)
   return setmetatable({...}, list_metatable)
end

-- Make a table usable as a list, without modifying any table entries
function list.from(tbl)
   if type(tbl)~="table" then error("arg not a table: " .. tostring(tbl)); end
   return setmetatable(tbl, list_metatable)
end

function list.is(obj)				    -- in scheme: list?
   return (getmetatable(obj)==list_metatable)
end

function list.length(obj)
   if list.is(obj) then return #obj; end
   error("arg not a list: " .. tostring(obj))
end

function list.validate_structure(obj)
   if (type(obj)~="table") then return false, "arg not a table"; end
   local len = 0
   -- Only numeric indices in our lists
   for k,v in pairs(obj) do
      if type(k)~="number" then return false, "non-numeric index: " .. tostring(k); end
      len = (k > len) and k or len
   end
   -- No gaps in the numbers
   for i=1,len do
      if not obj[i] then return false, "gap in indices at " .. tostring(i); end
   end
   return true
end

function list.null(ls)
   if not list.is(ls) then error("arg not a list: " .. tostring(ls)); end
   return (#ls==0)
end

function list.cons(elt, ls)
   if not list.is(ls) then error("arg not a list: " .. tostring(ls)); end
   return setmetatable({elt, table.unpack(ls)}, list_metatable)
end

function list.car(ls)
   if list.null(ls) then error("empty list"); end
   return ls[1]
end

-- N.B. This implementation of cdr breaks 'eq':
-- eq(cdr(l), cdr(l)) ==> false
function list.cdr(ls)
   if list.null(ls) then error("empty list"); end
   return setmetatable({ table.unpack(ls, 2) }, list_metatable)
end

function list.append(l1, ...)
   local result = list.new(table.unpack(l1))	    -- shallow copy
   for _, l in ipairs({...}) do
      table.move(l, 1, #l, #result+1, result)
   end
   return result
end

function list.andf(a, b, ...)
   if next{...} then error("andf takes exactly 2 args"); end
   return (a and b)
end

function list.orf(a, b, ...)
   if next{...} then error("orf takes exactly 2 args"); end
   return (a or b)
end

function list.equal(e1, e2)
   if list.is(e1) then
      if (e1==e2) then return true		    -- same table => same list
      elseif not list.is(e2) then return false
      elseif list.length(e1)~=list.length(e2) then return false
      else return list.reduce(list.andf, true, list.map(list.equal, e1, e2))
      end
   else
      -- compare atoms
      return (e1==e2)
   end
end

function list.member(elt, ls)
   if list.null(ls) then return false; end
   for _, item in ipairs(ls) do
      if list.equal(elt, item) then return true; end
   end
   return false
end

function list.last(ls)
   if list.null(ls) then error("empty list"); end
   return ls[#ls]
end

function list.tostring(ls)
   if list.null(ls) then return("{}"); end
   local str, elt_str
   for _,elt in ipairs(ls) do
      elt_str = ((type(elt)=="table" and list.is(elt) and list.tostring(elt)) or tostring(elt))
      if str then str = str .. ", " .. elt_str
      else str = "{" .. elt_str; end
   end
   return str .. "}"
end
   
list_metatable.__tostring = list.tostring

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
-- N.B. Only the first list's elements are present in the result.  The other lists provide
-- additional arguments to fn().
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

function list.reduce(fn, init, lst, i)
   i = i or 1
   if i > #lst then
      return init
   else
      return list.reduce(fn, fn(init, lst[i]), lst, i+1)
   end
end

function list.flatten(ls)
   if list.null(ls) then return ls;
   elseif list.is(list.car(ls)) then
      return list.append(list.flatten(list.car(ls)), list.flatten(list.cdr(ls)))
   else
      return list.cons(list.car(ls), list.flatten(list.cdr(ls)))
   end
end

function list.reverse(ls)
   if list.null(ls) then return ls;
   elseif #ls==1 then return ls;
   else return list.append(list.reverse(list.cdr(ls)), new(list.car(ls)))
   end
end

return list
