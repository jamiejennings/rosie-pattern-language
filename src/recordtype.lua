---- -*- Mode: Lua; -*- 
----
---- recordtype.lua   (was recordtype3.lua)
----
---- Inspired by the define-record Scheme macro by Jonathan Rees, and the Art
---- of the Meta-Object Protocol, except there are no objects here.
----
---- This version (1.3) is much faster than the first stable version (version
---- 1.1). Differences from the previous version (version 1.2) are: 
----
----   When a table is supplied as an argument to create an instance, that
----   table is converted into the instance.  A copy is not made, in order to
----   reduce the amount of garbage that needs to be collected.
----
----   The instance creator function has had some performance-related
----   enhancements.
----
---- Note: Version 1.1 dropped some functions that were rarely, if ever, used.
---- These include get_slot_function and set_slot_function.
----
---- (c) 2009, 2010, 2015 Jamie A. Jennings
---- Saturday, May 30, 2009
---- Saturday, June 19, 2010 (faster version)
---- Wednesday, June 30, 2010
---- Monday, September 28, 2015 (port to Lua 5.3)

--[[

-----------------------------------------------------------------------------
Usage
-----------------------------------------------------------------------------

  A record is a table with a fixed set of keys.  Only those keys can be set,
  and keys can be neither added or deleted.  N.B. No key can have a nil
  value!  Use recordtype.unspecified if you like, or any other value.

  The important function in this module is 'define', which is used to define a
  'recordtype' object with functions to create and work with instances of that
  type.

  To define a record type, you supply a prototype and a pretty name (any
  string).  The prototype is a table whose keys are the slots you want in
  records of this type, and whose values are the default values.
  E.g.
     > window = recordtype.define({width=100, height=400, color="red"}, "window")
     > door = recordtype.define({color="red", handed="left"}, "door")

  Instances are created by calling <recordtype>(...), which can be called
  either with no arguments or a table containing the slots that you wish to
  set.
  E.g.
     > w1=window()
     > print(w1.color, w1.width, w1.height)
     red        100     400
     > w3=window({color="cyan"})
     > print(w3.color, w3.width, w3.height)
     cyan	100	400
     > 

  Important note: When a table is supplied, that table is turned into the
  recordtype instance by setting its metatable.

  Slots are accessed and set using normal Lua table access techniques, i.e.
     > w1.color
     red
     > w1.color="green"
     > w1.color
     green

  You can check if a thing is a record of type <recordtype> by using the
  'is' function in <recordtype>. 
  E.g.
     > =window.is(w1)
     true

  You can obtain the pretty name for the type of a <recordtype> itself or of
  an instance using the type function from the recordtype module.  E.g.

     > =recordtype.type(window)
     window
     > =recordtype.type(w1)
     window
     > 

  You can print the contents of an instance using the convenience function <recordtype.print>,
  which is customizable.

     > window.print(w1)
     color	blue
     width	100
     height	400
     > 

  Lastly, you can often treat an instance like any other table, e.g.

     > for k,v in pairs(w1) do print(k,v) end
     color	blue
     width	100
     height	400
     > 
     > json.encode(w1)
     {"color":"blue","width":100,"height":400}
     > 

-----------------------------------------------------------------------------
Customization:
-----------------------------------------------------------------------------

  The following aspects of record types can be customized:
     <recordtype>.create_function for creating a record instance
     <recordtype>.tostring for converting an instace to a string (tostring)
     <recordtype>.print for printing the contents (slots) of a record

  In the case of creating an instance and converting an instance to a string,
  the custom function you supply will be called with the actual creator and
  the actual tostring function as the first argument.

-----------------------------------------------------------------------------
Details:
-----------------------------------------------------------------------------

  recordtype :== { 

      define(prototype, pretty_type_name, optional_creator) --> <recordtype>
	  --> defines a new <recordtype>, which is a table.  prototype defines
          --> the valid slots and provides default values for them.

      type(thing) --> <string> | nil
	  --> returns the pretty_type_name if thing is a <recordtype> or an
          --> <instance> of any <recordtype>.  otherwise, returns nil.
  }

  <recordtype> :== {  

       <recordtype>() --> <instance>
	   --> creates a new record instance with default values that were
	   --> provided in the prototype when <recordtype> was defined

       <recordtype>(initial_values_table) --> <instance>
	   --> turns initial_values_table into a new record instance, adding
	   --> default values for any missing slots

       <recordtype>.is(thing) --> <boolean>
	   --> predicate returns true if thing is a record of <recordtype>

       <recordtype>.type() --> <string>
	  --> returns the pretty name for the type of <recordtype>

       <recordtype>.tostring_function(instance_tostring, self)
           --> instance_tostring(self) returns a string describing self.  Your
           --> function must also return a string value.

       <recordtype>.create_function(create_instance, ...)
           --> create_instance(...) is used to actually create an instance.
           --> Your custom create_function can do whatever else it wants, but
           --> it must call create_instance in order to get a new instance.
           --> The new instance must be the return value from your function.

       <recordtype>.print(self)
	   --> Prints the data in self as follows:
           -->       for k,v in pairs(self) do print(k,v) end
           --> You can set <recordtype>.print to another function.
  }

]]--


-----------------------------------------------------------------------------
-- To do:

-- Keep a list of defined type names, and print a warning when redefining an
-- existing type name.

-- Consider supporting a weak population of instances for each type.

-- Is there a use case for accessing the type id of a record type, i.e. the
-- object that determines is?  After all, pretty type names are not
-- guaranteed to be unique.

-----------------------------------------------------------------------------

--require("strict")

if not string then
   error( "To use 'recordtype', you will also need to have the 'string' package available.", 2 )
end

-- 
-- Cache globals for code that might run under sandboxing 
--
local assert= assert
local string= string
local pairs= assert( pairs )
local error= assert( error )
local getmetatable= assert( getmetatable )
local setmetatable= assert( setmetatable )
local rawget= assert( rawget )
local rawset= assert( rawset )
local tostring = assert( tostring )
local print = assert( print )
local luatype = assert( type )
local pcall = assert( pcall )

local recordtype = {}

recordtype.ABOUT= 
{
    author= "Jamie A. Jennings <jj27700@gmail.com>",
    description= "Provides records implemented as tables with a fixed set of keys",
    license= "MIT/X11",
    copyright= "Copyright (c) 2010, 2015 Jamie A. Jennings",
    version= "1.3",
    lua_version= "5.3"
}


-----------------------------------------------------------------------------
-- Utilities
-----------------------------------------------------------------------------

-- We need a unique value with which we can identify that a table is a record
-- instance.  As recommended by the Lua creators, we'll create an empty table
-- to use as our unique object.

local function new_unique_object()
   return {};
end

local recordtypemark = new_unique_object();

local function apply(apply_f, ...)
   return apply_f(...)
end

-----------------------------------------------------------------------------
-- Instance functions
-----------------------------------------------------------------------------

local function slot_error(self, key)
   error("record error: slot \'"..key..
	 "\' not valid for ".. tostring(self), 2)
end

local function not_an_instance_error(thing, typename)
   error("record error: ".. tostring(thing)..
      " is not an instance of ".. typename, 2)
end

local function make_print_function(typecheck, typename)
   return function(obj)
	     if typecheck(obj) then
		for k,v in pairs(obj) do
		   print(k,v)
		end
	     else
		not_an_instance_error(obj, typename)
	     end
	  end
end

local function create_metatable(recordtype, recordtypeid, pretty_type_name, tostring, prototype)
   local mt = {
      __metatable = true;		-- prevents tampering with the metatable
      -- If a record slot's value is nil, references to that slot will trigger the __index and
      -- __newindex functions here, for getting and setting, respectively.
      __index = function(self, key)
		   if rawget(prototype, key) then return nil;
		   else slot_error(self, key); 
		   end; 
		end;
      __newindex = function(self, key, value)
		      if rawget(prototype, key) then rawset(self, key, value);
		      else slot_error(self, key); 
		      end; 
		   end;
      __tostring = tostring;

      __pow = function(self, id) return id==recordtypeid end;
      __unm = function() return recordtype end;
   }
   return mt;
end

local function instance_arg_error(pretty_type_name, initial_values)
   error("recordtype error: argument to " 
	 .. pretty_type_name .. " creator is not a table: "
	 .. tostring(initial_values), 3)
end

local function make_instance_creator(recordtype, prototype, pretty_type_name, recordtypeid, tostring_function)
   local prototype_len = 0;
--   setmetatable(prototype, {__index = slot_error; __newindex = slot_error});
   local metatable = create_metatable(recordtype, recordtypeid, pretty_type_name, tostring_function, prototype)
   for k,v in pairs(prototype) do prototype_len = prototype_len + 1; end
   return -- the instance creator function
     function(initial_values)
	local initial_values = initial_values or {}
	if luatype(initial_values)~="table" then
	   instance_arg_error(pretty_type_name, initial_values)
	end
	-- Check for invalid slot names
	local initial_values_len = 0
	for k,v in pairs(initial_values) do
	   initial_values_len = initial_values_len + 1;
	   if rawget(prototype, k)==nil then 
	      slot_error(recordtype, k)
	   end
	end -- for
        -- Turn the argument, initial_values, into the record instance
        -- Set the default value for any slots not in initial_values
        if initial_values_len~=prototype_len then
           for k,v in pairs(prototype) do
              if initial_values[k]==nil then initial_values[k] = v; end
           end -- for
	end -- if we need to fill in missing values
	setmetatable(initial_values, metatable);
	return initial_values
     end -- create_instance
end -- make_instance_creator

-- Is an object a recordtype? (a type, not an instance!)

local function has_recordmark(thing)
   return (thing^recordtypemark)
end

function recordtype.is(thing, more)
   if more then
      error("record error: too many arguments to 'is' function: " ..
	    tostring(thing) .. ", " .. tostring(more))
   end
   local status, result = pcall(has_recordmark, thing)
   return (status and result)
end

-----------------------------------------------------------------------------
-- Define a new and unique record type
-----------------------------------------------------------------------------

local function is_instance_error(thing, more)
   error("record error: too many arguments to 'is' function: " ..
	 tostring(thing) .. ", " .. tostring(more))
end

local function exp_function(thing, recordtypeid)
   return (thing^recordtypeid)
end

local function make_is_instance_function(recordtypeid)
   return function(thing, more) 
	     if more then
		is_instance_error(thing, more)
	     end
	     local status, retval = pcall(exp_function, thing, recordtypeid);
	     return (status and retval)
	  end
end

local function make_type_function(pretty_type_name)
   return function(more)
	     if more then
		error("record error: too many arguments to 'type' function: " 
		      .. tostring(more))
	     end
	     return pretty_type_name
	  end
end

function recordtype.define(prototype, pretty_type_name)
   if not pretty_type_name then pretty_type_name = "anonymous"; end
   if luatype(pretty_type_name)~="string" then
      error("record error: recordtype name not a string: " .. tostring(pretty_type_name))
   end

   -- Ensure all slot names are strings before we go further
   for slot, _ in pairs(prototype) do
      if luatype(slot) ~= "string" then
	 error("recordtype error: slot name not a string: ".. tostring(slot), 2)
      end
   end

   local recordtypeid = new_unique_object();
   local rt = {};
   local isfunction = make_is_instance_function(recordtypeid);
   rt.print = make_print_function(isfunction, pretty_type_name);
   rt.type = make_type_function(pretty_type_name);
   rt.is = isfunction;

   rt.tostring_function = apply;
   local actual_tostring = function() return "<"..pretty_type_name..">"; end;
   local tostring_function =
      function(self)
	 return rt.tostring_function(actual_tostring, self)
      end;

   rt.create_function = apply;
   local actual_creator = make_instance_creator(rt,
						prototype,
						pretty_type_name, 
						recordtypeid,
						tostring_function);
   local create_function =
      function(self, ...)
	 return rt.create_function(actual_creator, ...)
      end;

   setmetatable(rt, 
		{__call=create_function;
		 __tostring=function(self) 
			       return "<recordtype: "..pretty_type_name..">"
			    end;
		 __pow = function(self, mark) 
			    return mark==recordtypemark
			 end;
	      })
   return rt
end

local function get_recordtype(obj)
   return (- obj)
end

function recordtype.type(obj)
   if recordtype.is(obj) then 
      return obj.type()
   else
      status, result = pcall(get_recordtype, obj)
      if status then
	 return result.type()
      else
	 return luatype(obj)
      end
   end
end

recordtype.unspecified = setmetatable({}, {__tostring = function (self) return("<unspecified>"); end; })


--print("Beta version of recordtype 1.3 loaded (recordtype3)")

return recordtype
