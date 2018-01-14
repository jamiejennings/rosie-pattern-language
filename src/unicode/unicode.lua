-- -*- Mode: Lua; -*-                                                                             
--
-- unicode.lua
--
-- © Copyright Jamie A. Jennings 2018.
-- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
-- AUTHOR: Jamie A. Jennings

local rosie = require("rosie")
import = rosie.import
local list = import("list")
local violation = import("violation")


local engine = rosie.engine.new()
local ok, pkgname, errs = engine:loadfile("ucd.rpl")
if not ok then
   error(table.concat(list.map(violation.tostring, errs), "\n"))
end

ucd = dofile("ucd.lua")
enumerated = dofile("enumerated.lua")
util = dofile("util.lua")

UNICODE_VERSION = "10.0.0"
UCD_DIR = assert(rosie.env.ROSIE_HOME) .. "/src/unicode/UCD-" .. UNICODE_VERSION .. "/"

ReadmeFile = "ReadMe.txt"

UnicodeDataFile = "UnicodeData.txt"

PropertyFiles = { {"Block", "Blocks.txt"},
		  {"Script", "Scripts.txt"},
		  {"Category", "extracted/DerivedGeneralCategory.txt"},
		  {"Property", "PropList.txt"},
		  {"Property", "extracted/DerivedBinaryProperties.txt"},
		  {"LineBreak", "extracted/DerivedLineBreak.txt"},
		  {"NumericType", "extracted/DerivedNumericType.txt"},
		  {"GraphemeBreak", "auxiliary/GraphemeBreakProperty.txt"},
		  {"SentenceBreak", "auxiliary/SentenceBreakProperty.txt"},
		  {"WordBreak", "auxiliary/WordBreakProperty.txt"},
	       }

character_db = nil

as_peg = false
property_db = {}
source_property_db = {}
function populate_property_db()
   for _, entry in ipairs(PropertyFiles) do
      local property_name = entry[1]
      local filename = entry[2]
      local new_source, new = enumerated.processPropertyFile(engine, filename, property_name, as_peg)
      if not property_db[property_name] then
	 property_db[property_name] = new
	 source_property_db[property_name] = new_source
      else
	 -- A property by the same name exists, but we can merge them if the value sets
	 -- for each are unique
	 local existing = property_db[property_name]
	 for value, pattern in pairs(new) do
	    if existing[value] then
	       error("Value collision for " .. property_name .. ": " .. value)
	    else
	       existing[value] = pattern
	    end
	 end
      end
   end
end

header_top = [[
-- DO NOT EDIT. THIS FILE WAS GENERATED FROM THE Unicode Character Database.
-- About the Unicode Character Database:
-- 
]]
header_rest = [[
-- 
-- This file © Copyright IBM, 2018.
-- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
]]

function construct_header()
   local nl, err = io.lines(UCD_DIR .. "/" .. ReadmeFile)
   if not nl then error(err); end
   local line = nl()
   header = header_top
   while line do
      if line:sub(1,1)=="#" then
	 header = header .. "--    " .. line .. "\n"
      end
      line = nl()
   end
   header = header .. header_rest
end

-- -----------------------------------------------------------------------------
-- ASCII character classes from the Posix locale (also called C locale)
-- -----------------------------------------------------------------------------

ascii_patterns = {}

function ranges_from_locale_peg(peg)
   local ranges = {}
   local start = nil
   for c = 0x0, 0x7F do
      if peg:match(string.char(c)) then
	 if not start then start = c; end
      else
	 if start then
	    -- from start to c-1 is a valid range of ascii chars for this peg
	    table.insert(ranges, {start, c - 1})
	    start = nil
	 end
      end
   end
   if start then table.insert(ranges, {start, start}); end
   return ranges
end

function rpl_from_locale_peg(name, peg)
   local ranges = ranges_from_locale_peg(peg)
   local rpl_for_name = util.compile_all_ranges({[name] = ranges}, false)
   return rpl_for_name[name]
end

function read_ascii()
   locale = lpeg.locale()
   for name, peg in pairs(locale) do
      ascii_patterns[name] = rpl_from_locale_peg(name, peg)
   end
   local engine = rosie.engine.new()
   for name, source in pairs(ascii_patterns) do
      print("Compiling", name, source)
      local rplx, errs = engine:compile(source)
      if not rplx then
	 error(table.concat(list.map(violation.tostring, errs), "\n"))
      end
      local in_range_errors = 0
      local peg_out_range_errors = 0
      local rpl_out_range_errors = 0
      for c = 0x0, 0x7F do
	 local pok = locale[name]:match(string.char(c))
	 local rok = rplx:match(string.char(c))
	 if (pok and not rok) or (rok and not pok) then
	    print(string.format("%s failed at char \\x%02x", name, c))
	    in_range_errors = in_range_errors + 1
	 end
      end -- for 0x0 - 0x7F
      for c = 0x80, 0xff do
	 if locale[name]:match(string.char(c)) then
	    print(string.format("peg matches non-ascii character \\x%02x", c))
	    peg_out_range_errors = peg_out_range_errors + 1
	 end
	 if rplx:match(string.char(c)) then
	    print(string.format("rpl matches non-ascii character \\x%02x", c))
	    rpl_out_range_errors = rpl_out_range_errors + 1
	 end      
      end -- for 0x80 - 0xFF
      if in_range_errors == 0 then
	 print("In range ascii values tested OK")
      end
      if (peg_out_range_errors == 0) and (rpl_out_range_errors == 0) then
	 print("Out of range values tested OK")
      else
	 print("ERRORS with bytes outside of ascii range")
      end
   end -- for each compiled rpl pattern
end


-- -----------------------------------------------------------------------------
-- Top level:  read(); write()
-- -----------------------------------------------------------------------------

function read()
   construct_header()
   character_db = ucd.processUnicodeData(engine, UnicodeDataFile)
   populate_property_db()
   os.setlocale("C")
   read_ascii()
   source_property_db.ascii = ascii_patterns
end

function write(optional_directory)
   optional_directory = optional_directory or "/tmp"
   for propname, patterns in pairs(source_property_db) do 
      local filename = (optional_directory .. "/" .. propname .. ".rpl")
      print("Writing " .. filename)
      local f, err = io.open(filename, 'w')
      if not f then error(err); end
      f:write(header, "\n")
      f:write("package ", propname, "\n\n")
      for patname, patsource in pairs(patterns) do
	 f:write(patname, " = ", patsource, "\n")
      end
      f:close()
   end
end


