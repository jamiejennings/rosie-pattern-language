-- -*- Mode: Lua; -*-                                                                             
--
-- unicode.lua
--
-- © Copyright Jamie A. Jennings 2018.
-- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
-- AUTHOR: Jamie A. Jennings

local rosie = require("rosie")
local engine = rosie.engine.new(); engine:loadfile("ucd.rpl")

ucd = dofile("ucd.lua")
enumerated = dofile("enumerated.lua")

UCD_DIR = assert(rosie.env.ROSIE_HOME) .. "/src/unicode/UCD-10.0.0/"

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

character_db = ucd.processUnicodeData(engine, UnicodeDataFile)

property_db = {}
for _, entry in ipairs(PropertyFiles) do
   local property_name = entry[1]
   local filename = entry[2]
   local new = enumerated.processPropertyFile(engine, filename, property_name)
   if not property_db[property_name] then
      property_db[property_name] = new
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




