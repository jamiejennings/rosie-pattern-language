---- -*- Mode: Lua; -*- 
----
---- utils.lua
----
---- (c) 2015, Jamie A. Jennings
----

math = require "math"
lpeg = require "lpeg"

-- Split a string into lines, returning them one at a time
function string_nextline(str)
   local nextpos = 1
   local endpos = #str
   local up_to_eol = lpeg.C((P(1) - P"\n")^0) * (P("\n") + P(-1)) * lpeg.Cp()
   return function ()
	     if nextpos > endpos then return nil; end;
	     local line;
	     line, nextpos = up_to_eol:match(str, nextpos)
	     return line
	  end
end

----------------------------------------------------------------------------------------
-- Table stuff
----------------------------------------------------------------------------------------

-- Copy all entries in src table to dest table.  If no dest table passed in, create a new one. 
function copy_table(src, dest)
   dest = dest or {}
   for k,v in pairs(src) do dest[k] = v; end
   return dest
end

-- Treating tables as lists with integer indicies, append them and produce a new list.
function table_append(...)
   result = {}
   for _,list in ipairs({...}) do
      table.move(list, 1, #list, #result+1, result)
   end
   return result
end

function pretty_print_table(t, max_item_length, js_style)
   if not t then
      io.stderr:write("Error: pretty_print_table called with nil table\n");
      return;
   end
   io.write(table_to_pretty_string(t, max_item_length, js_style), "\n")
end
   
local function limit(s, max_length)
   if #s > max_length then
      return s:sub(1,max_length).."..."
   else
      return s
   end
end

local function keys_are_numbers(t)
   for k,_ in pairs(t) do
      if type(k)~="number" then return false; end
   end
   return true
end

function table_to_pretty_string(t, max_item_length, js_style)
   if not t then
      error("Nil table")
      return;
   end
   local max = max_item_length or 30
   local delta = 2
   local sep, open, close, key_value_sep = ", ", "{", "}", ": "
   local js_array_open, js_array_close = "[", "]"
   local pretty_print;
   local key = function(k, tbl, array_p, sep, indent)
		  local fmt = (js_style and "%q") or "%s"
		  if array_p then
		     return "", 0
		  else 
		     if type(k)=="number" then
			return tostring(k) .. key_value_sep, #tostring(k) + #key_value_sep + 1
		     else
			return string.format(fmt, k) .. key_value_sep ..
			((tbl and ("\n" .. string.rep(" ", indent+delta))) or ""), delta+1
		  end
	       end
	    end
   pretty_print = 
      function(t, indent, output)
	 local js_array = js_style and keys_are_numbers(t)
	 if js_array then output = output .. js_array_open
	 else output = output .. open; end
	 local offset
	 for k,v in pairs(t) do
	    local pretty_k
	    if k~=next(t) then output = output .. string.rep(" ", indent); end
	    pretty_k, offset = key(k, (type(v)=="table") and next(v), js_array, key_value_sep, indent)
	    output = output .. pretty_k
	    if type(v)=="table" then
	       output = output .. pretty_print(v, indent + offset, "")
            elseif type(v)=="string" then
	       output = output .. string.format("%q", limit(v,max))
	    else
	       output = output .. limit(tostring(v),max)
	    end -- switch on type(v)
	    if next(t, k) then output = output .. sep .. "\n"; end
	 end -- for pairs
	 if js_array then output = output .. js_array_close
	 else output = output .. close; end
	 return output
      end -- function pretty_print
   return pretty_print(t, 0, "")
end

if table then
   table.print = pretty_print_table;
   table.tostring = table_to_pretty_string;
end

----------------------------------------------------------------------------------------
-- JSON printing
----------------------------------------------------------------------------------------

function prettify_json(s)
   local t = json.decode(s)
   return table_to_pretty_string(t, nil, true)
end


----------------------------------------------------------------------------------------
-- Date/time stuff
----------------------------------------------------------------------------------------

local function leap_years_through(year)
   local idiv = function(n, d) return n//d; end;
   return idiv(year, 4) - idiv(year, 100) + idiv(year, 400)
end

local leap_years_through_1970 = leap_years_through(1970)

local function is_leap_year(year)
   if (year % 4) ~= 0 then return false		      -- leap years are divisible by 4
   elseif (year % 100) ~= 0 then return true	      -- but not also divisible by 100
   elseif (year % 400) == 0 then return true	      -- unless also divisible by 400
   else return false
   end
end

local mon_lengths = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
--local 
months_to_days_cumulative = { 0 }
for i = 2, 12 do
   months_to_days_cumulative[i] = months_to_days_cumulative[i-1]  + mon_lengths[i-1]
end

--local 
function day_of_year(year, month, day)
   local total = months_to_days_cumulative[month]
   if month > 2 and is_leap_year(year) then total = total + 1; end
   return total + day
end

local seconds_per_day = (60*60*24)
local seconds_per_hour = (60*60)

local tz_factor = {}; tz_factor["+"] = -1; tz_factor["-"] = 1;

local function tz_offset(sign, hours, mins)
   if sign then
      -- cast to numbers
      hours = tonumber(hours)
      mins = tonumber(mins)
      return tz_factor[sign] * (hours*seconds_per_hour) + (mins*60)
   else return 0
   end
end

-- We rely on the arguments to be within their normal ranges.  The arguments can be strings or
-- numbers, except for tz_sign, which is always either "-" or "+" or nil.
-- Return an integer number of milliseconds, ignoring any fractions of a millisecond.
function time_since_epoch(year, month, day, hour, min, sec, tz_sign, tz_hours, tz_mins)
   -- cast to numbers, in case they were passed as strings such as after parsing
   local year = tonumber(year)
   local month = tonumber(month)
   local day = tonumber(day)
   local hour = tonumber(hour)
   local min = tonumber(min)
   local sec = tonumber(sec)
   local days_since_epoch = day_of_year(year, month, day) + 
                            365 * (year - 1970) + 
                           (leap_years_through(year-1) - leap_years_through_1970) - 1;
   local seconds = (days_since_epoch * seconds_per_day)
          + (hour * seconds_per_hour)
          + (min * 60)
          + sec					      -- note: can be fractional
          + tz_offset(tz_sign, tz_hours, tz_mins);    -- is this really so simple?
   return math.floor(seconds * 1000.0)
end

function test_time_since_epoch()
   print("NOT thoroughly testing leap years or timezone offsets (yet)...")
   assert(time_since_epoch(1970,1,1,0,0,1)==1000)
   assert(time_since_epoch(1971,1,1,0,0,0)==31536000000)
   assert(time_since_epoch(1971,2,1,0,0,0)==34214400000)
   assert(time_since_epoch(1971,2,2,0,0,0)==34300800000)
   assert(time_since_epoch(1971,2,2,13,0,0)==34347600000)
   assert(time_since_epoch(1971,2,2,13,50,0)==34350600000)
   assert(time_since_epoch(1971,2,2,13,50,22)==34350622000)
   assert(time_since_epoch(1971,2,2,13,50,22.123)==34350622123)
   assert(time_since_epoch(1971,2,2,13,50,22.1235)==34350622123) -- ignoring 0.5 ms
   assert(time_since_epoch(1971,2,2,13,50,22.1239)==34350622123) -- ignoring 0.9 ms

   -- Leap years affect the following cases...
   assert(time_since_epoch(1980,1,1,00,00,00)==315532800000)

   -- Time zones affect the following cases...
   assert(time_since_epoch(1980,1,1,00,00,00,"-",0,0)==315532800000)
   assert(time_since_epoch(1980,1,1,00,00,00,"-",0,1)==315532860000)
   assert(time_since_epoch(1980,1,1,00,00,00,"-",1,0)==315536400000)
   assert(time_since_epoch(1980,1,1,00,00,00,"-",5,0)==315550800000)
   assert(time_since_epoch(1980,1,1,00,00,00,"+",5,0)==315514800000)
   assert(time_since_epoch(1980,1,1,00,00,00,"+",5,33)==315516780000)
   assert(time_since_epoch(2015, 8, 23, 3, 36, 25)==1440300985000)
   assert(time_since_epoch(2015, 8, 23, 3, 36, 25, "-", 4, 0)==1440315385000)

   print("Done.")
end

---------------------------------------------------------------------------------------------------
-- Misc
---------------------------------------------------------------------------------------------------

function uuid()
   local pcall_success, handle = pcall(io.popen, "/usr/bin/env uuidgen");
   if not (pcall_success and handle) then
      error("Command uuidgen failed.  Either Lua io.popen is not available "..
	    "on this platform or uuidgen is not installed. Try installing package uuid-runtime.")
   end
   local uuid = handle:read()
   local os_success, _, os_status = handle:close()
   if not os_success and os_status==0 then
      error("Command uuidgen failed in some strange way.")
   end
   return uuid
end

function warn(...)
   if not QUIET then
      io.stderr:write("Warning: ")
      for _,v in ipairs({...}) do
	 io.stderr:write(tostring(v))
      end
      io.stderr:write("\n")
   end
end

function extract_source_line_from_pos(source, pos)
   local eol = string.find(source, "\n", pos, true);
   local start;
   local count = 1;
   if not eol then eol = #source;
   else eol = eol - 1;				    -- let's omit the newline itself
   end
   local candidate = string.find(source, "\n", 1, true)
   if not candidate or (candidate > pos)
   then
      return string.sub(source, 1, eol), pos, count;
   else
      while candidate and (candidate <= pos) do
	 start = candidate+1;
	 count = count + 1;
	 candidate = string.find(source, "\n", candidate+1, true)
      end
   end
   -- return the line, and the new position of pos in the line, and the number of this line
   return string.sub(source, start, eol), pos-start, count
end
      
