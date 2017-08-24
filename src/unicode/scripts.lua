

-- TO DO:
--
-- GENERALIZE: Most of this code will work for all the UCD properties files.
-- OPTIMIZE: Adjacent ranges can sometimes be combined.
-- DERIVE the union classes L, M, N, S, P, Z, and C


list = require "list"
map = list.map

--f = io.open("/Users/jjennings/Work/Dev/private/rosie-plus/unicode/UCD/Scripts.txt")

codepoint = lpeg.R("09", "AF")^4		    -- 4 or more hex digits
scripts_codepoints = lpeg.Ct(lpeg.C(codepoint) * (lpeg.P("..") * lpeg.C(codepoint))^-1)
scripts_property = lpeg.C((lpeg.P(1)-lpeg.S(" ;#"))^1)
property_peg = scripts_codepoints * lpeg.S(" ")^0 * lpeg.S(";") * lpeg.S(" ")^0 * scripts_property

local function hex_to_int(str) return tonumber(str, 16); end

function read_ucd_property_file(filename)
   local db = {}
   local nl = io.lines(filename)
   local line = nl()
   while line do
      local cp, prop = property_peg:match(line)
      if cp then
	 cp = map(hex_to_int, cp)
	 if #cp==1 then table.insert(cp, cp[1]); end -- ranges always have start/finish
	 if db[prop] then
	    table.insert(db[prop], cp)
	 else
	    db[prop] = { cp }
	 end
      end
      line = nl()
   end
   return db
end

function read_ucd_scripts()
   return read_ucd_property_file("/Users/jjennings/Work/Dev/private/rosie-plus/unicode/UCD/Scripts.txt")
end

					   
function test_all_codepoints_against_all_properties(prop_patterns, prop_ranges)
   local j=0
   for prop_name, prop_pattern in pairs(prop_patterns) do
      io.write("Testing property: " .. prop_name .. " ")
      local n_chars, n_ok, n_fail =
	 test_all_codepoints_against_property(prop_name, prop_pattern, prop_ranges[prop_name])
      j = j+1
      assert(n_chars == (n_ok + n_fail), "totals don't add up")
      io.write(tostring(n_chars), " characters tested, ", tostring(n_fail), " failures\n")      
   end -- for each property
   io.write(tostring(j), " Properties tested\n")
end
   
codepoint_min = 0x0
codepoint_max = 0x10FFFF

function test_all_codepoints_against_property(name, pattern, ranges)
   -- ranges is expected to be the ground truth.  we are testing the pattern.
   -- ranges is expected to be sorted, and non-overlapping.
   local count=0;				    -- number of characters tested
   local ok=0;
   local err=0;
   local range_index = 1
   for codepoint = codepoint_min, codepoint_max do
      local match = pattern:match(utf8.char(codepoint))

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
	    print(string.format("\nPattern failure: %s matched (%X)", name, codepoint))
	    err=err+1
	 else
	    ok = ok+1
	 end
      else
	 -- we are not beyond the end of all the ranges, AND this codepoint is in range.
	 -- ==> answer should be YES.
	 if not match then
	    print(string.format("\nPattern failure: %s failed (%X)", name, codepoint))
	    err=err+1
	 else
	    ok = ok+1
	 end
      end
      count = count + 1
   end -- for all codepoints
   return count, ok, err
end



sc_ranges = read_ucd_scripts()
i = 0
for k,_ in pairs(sc_ranges) do i = i+1; print(k); end
print(i, "script designations found")
sc_patterns = compile_all_ranges(sc_ranges)
test_all_codepoints_against_all_properties(sc_patterns, sc_ranges)

