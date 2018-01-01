-- -*- Mode: Lua; -*-                                                                             
--
-- unicode.lua
--
-- © Copyright Jamie A. Jennings 2018.
-- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
-- AUTHOR: Jamie A. Jennings

ucd = dofile("ucd.lua")

UCD_DIR = assert(rosie.env.ROSIE_HOME) .. "/src/unicode/UCD-10.0.0/"

UnicodeDataFile = "UnicodeData.txt"
PropertyFiles = { "extracted/DerivedBinaryProperties",
		  "extracted/DerivedGeneralCategory",
		  "extracted/DerivedLineBreak",
		  "extracted/DerivedNumericType",
		  "auxiliary/GraphemeBreakProperty",
		  "auxiliary/SentenceBreakProperty",
		  "auxiliary/WordBreakProperty",
	       }

character_db, gc_patterns = ucd.processUnicodeData(UnicodeDataFile)



