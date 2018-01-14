-- -*- Mode: Lua; -*-                                                                             
--
-- enumerated.lua
--
-- © Copyright Jamie A. Jennings 2016, 2017, 2018.
-- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
-- AUTHOR: Jamie A. Jennings



-- TO DO:
--
-- GENERALIZE: Most of this code will work for all the UCD properties files.
-- OPTIMIZE: Adjacent ranges can sometimes be combined.
-- DERIVE the union classes L, M, N, S, P, Z, and C

local enumerated = {}

local list = import("list")
local violation = import("violation")
local util = dofile("util.lua")

-- Note: When comparing block names, casing, whitespace, hyphens, and underbars
--       are ignored.  For example, "Latin Extended-A" and "latin extended a"
--       are equivalent.  We will canonicalize all Unicode values, in case other
--       properties have values with spaces or dashes.
function canonicalize_value(val)
   return (val:gsub(' ', '_'):gsub('-','_'))
end

local function storeEnumeratedProperty(data, ranges)
   assert(data.type=='EnumeratedProp_line')
   data = data.subs[1]
   if data.type=='comment' or data.type=='blank_line' then return; end
   assert(data.type=='EnumeratedProp')
   
   local start, finish
   if data.subs[1].type=='codePoint' then
      start = assert(tonumber(data.subs[1].data, 16))
      finish = start
   elseif data.subs[1].type=='codePointRange' then
      local codepoints = { data.subs[1].subs[1], data.subs[1].subs[2] }
      start = assert(tonumber(codepoints[1].data, 16))
      finish = assert(tonumber(codepoints[2].data, 16))
   else
      error("first field not codepoint or range of codepoints: ", data.subs[1].type)
   end

   assert(data.subs[2].type=='propertyName')
   local property_value = canonicalize_value(data.subs[2].data)

   if not ranges[property_value] then ranges[property_value] = {}; end
   table.insert(ranges[property_value], {start, finish})
end

local function loadPropertyFile(engine, filename)
   print("Reading", filename)
   local ranges = {}
   local parser = engine:compile("EnumeratedProp_line")
   local nl = util.make_nextline_function(filename)
   local line = nl()
   while(line) do
      local data = parser:match(line)
      if not data then
	 print(string.format("parse error in file %s at line %d: %q", filename, i, line))
      else
	 storeEnumeratedProperty(data, ranges)
      end
      line = nl()
   end
   return ranges
end

-- -----------------------------------------------------------------------------
-- Testing
-- -----------------------------------------------------------------------------

local codepoint_min = 0x0
local codepoint_max = 0x10FFFF

local function test_all_codepoints_against_value(name, pattern, ranges, match_fn)
   -- ranges is expected to be the ground truth.  we are testing the generated pattern.
   -- ranges is expected to be sorted, and non-overlapping.
   local count=0;				    -- number of characters tested
   local ok=0;
   local err=0;
   local range_index = 1
   for codepoint = codepoint_min, codepoint_max do
      local match = match_fn(pattern, utf8.char(codepoint))
      -- now compute the expected answer
      while ranges[range_index] and (codepoint > ranges[range_index][2]) do
	 -- advance the range_index to one that includes codepoint
	 range_index = range_index + 1
      end
      if (not ranges[range_index]) or (codepoint < ranges[range_index][1]) then
	 -- we are beyond the end of all the ranges for this property, OR
	 -- this codepoint is before the current range.
	 -- ==> answer should be NO.
	 if match then
	    print(string.format("** Pattern failure: %s matched (U+%X)", name, codepoint))
	    err=err+1
	 else
	    ok = ok+1
	 end
      else
	 -- we are not beyond the end of all the ranges, AND this codepoint is in range.
	 -- ==> answer should be YES.
	 if not match then
	    print(string.format("** Pattern failure: %s failed (U+%X)", name, codepoint))
	    err=err+1
	 else
	    ok = ok+1
	 end
      end
      count = count + 1
   end -- for all codepoints
   return count, ok, err
end

local function test_all_codepoints_against_all_values(value_patterns, value_ranges, match_fn)
   local j=0
   for prop_name, prop_pattern in pairs(value_patterns) do
      io.write("Testing value: " .. prop_name .. " ")
      local n_chars, n_ok, n_fail =
	 test_all_codepoints_against_value(prop_name,
					   prop_pattern,
					   value_ranges[prop_name],
					   match_fn)
      j = j+1
      assert(n_chars == (n_ok + n_fail), "totals don't add up")
      io.write(tostring(n_chars), " characters tested, ", tostring(n_fail), " failures\n")      
   end -- for each property
   io.write(tostring(j), " values tested\n")
end
   
local function test_property(property_name, patterns, ranges, match_fn)
   print("Testing property: " .. property_name)
   test_all_codepoints_against_all_values(patterns[property_name],
					  ranges[property_name],
					  match_fn)
end

-- -----------------------------------------------------------------------------
-- Top level
-- -----------------------------------------------------------------------------

function enumerated.processPropertyFile(engine, filename, property_name, as_peg)
   local ranges = loadPropertyFile(engine, filename)
   local i = 0;
   for _,_ in pairs(ranges) do i = i + 1; end
   print("Property", property_name, "has", i, "values")
   print("Compiling ranges")
   local source_patterns = {}
   local patterns = util.compile_all_ranges(ranges, as_peg)
   if not as_peg then
      source_patterns = patterns
      patterns = {}
      for name, source in pairs(source_patterns) do
	 print("Compiling", name, source)
	 local rplx, errs = engine:compile(source)
	 if not rplx then
	    error(table.concat(list.map(violation.tostring, errs), "\n"))
	 end
	 patterns[name] = assert(rplx.pattern.peg)
      end
   end -- if not as_peg
   test_property(property_name,
		 {[property_name]=patterns},
		 {[property_name]=ranges},
		 (as_peg and lpeg.match or lpeg.rmatch))
   return source_patterns, patterns
end



return enumerated


