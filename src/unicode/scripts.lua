-- -*- Mode: Lua; -*-                                                                             
--
-- scripts.lua
--
-- © Copyright Jamie A. Jennings 2016, 2017.
-- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
-- AUTHOR: Jamie A. Jennings

-- Rules of thumb in deciding what to support:
-- 
--   Generative data is usually NOT supported.  This is our term for data used to generate (and
--   sometimes manipulate) renderings.  E.g. Canonical Combining Class, Special Casing Conditions.
--
--   Contributory properties are NOT supported.  These are defined in Unicode TR#44, Section 5.5
--   as "incomplete by themselves and are not intended for independent use."
--
--   Properties that do not appear to be useful for matching (to us, at this moment, based on
--   necessarily limited knowledge of the matching tasks faced by Rosie users).  E.g. Age, Name,
--   Bidi Class.
--
-- 
-- Unicode character properties are extracted from 3 sources in the UCD:
--
-- (1) UnicodeData.txt
--     Fields:
--     (0) Codepoint in hex
--     (1) Name
--     (2) General Category (Enumeration)
--     (3) Canonical Combining Class
--     (4) Bidi Class (Enumeration)
--     (5) Decomposition Type and Mapping
--     (6,7,8) Numeric Type and Value
--     (9) Bidi Mirrored (Binary)
--     (10,11) Obsolete
--     (12) Simple Uppercase Mapping (Codepoint)
--     (13) Simple Lowercase Mapping (Codepoint)
--     (14) Simple Titlecase Mapping (Codepoint)
--
-- (2) Property files containing "Catalog" or "Enumeration" property types, which are guaranteed
-- to be partitions (Unicode TR#44, Section 5.2):
--     Block
--     Script
--     LineBreak
--     GraphemeBreakProperty
--     SentenceBreakProperty
--     WordBreakProperty
--     The rest are not supported in Rosie Pattern Language
--     
-- (3) Property files containing "Binary" property types
--     PropList.txt (x = contributory property, "not intended for independent use"
--       ASCII_Hex_Digit
--       Bidi_Control
--       Dash
--       Deprecated
--       Diacritic
--       Extender
--       Hex_Digit
--       Hyphen
--       IDS_Binary_Operator
--       IDS_Trinary_Operator
--       Ideographic
--       Join_Control
--       Logical_Order_Exception
--       Noncharacter_Code_Point
--       x Other_Alphabetic
--       x Other_Default_Ignorable_Code_Point
--       x Other_Grapheme_Extend
--       x Other_ID_Continue
--       x Other_ID_Start
--       x Other_Lowercase
--       x Other_Math
--       x Other_Uppercase
--       Pattern_Syntax
--       Pattern_White_Space
--       Prepended_Concatenation_Mark
--       Quotation_Mark
--       Radical
--       Regional_Indicator
--       Sentence_Terminal
--       Soft_Dotted
--       Terminal_Punctuation
--       Unified_Ideograph
--       Variation_Selector
--       White_Space
--     DerivedCoreProperties.txt
--       Alphabetic
--       Case_Ignorable
--       Cased
--       Changes_When_Casefolded
--       Changes_When_Casemapped
--       Changes_When_Lowercased
--       Changes_When_Titlecased
--       Changes_When_Uppercased
--       Default_Ignorable_Code_Point
--       Grapheme_Base
--       Grapheme_Extend
--       Grapheme_Link
--       ID_Continue
--       ID_Start
--       Lowercase
--       Math
--       Uppercase
--       XID_Continue
--       XID_Start
--
-- Case mappings supported in RPL are derived from:
--   UnicodeData.txt
--     (12) Simple Uppercase Mapping (Codepoint)
--     (13) Simple Lowercase Mapping (Codepoint)
--     (14) Simple Titlecase Mapping (Codepoint)
--   SpecialCasing.txt (conditions are not supported, as they are generative)
--     to lower (Codepoint+)
--     to title (Codepoint+)
--     to upper (Codepoint+)
-- 
--   On character equivalence and normalization:
--
--   Rosie does not understand Unicode character equivalences.  An RPL literal string containing
--   the single codepoint 00F4, which renders as ô, will match the UTF-8 encoding of 00F4 in the
--   input, but not the sequence 006F (o) followed by 0302 ( ̂), which is its NFD-decomposed
--   equivalent. 
-- 
--   How to address such equivalences during matching is an open design question.  A design point
--   for Rosie is that the input is read-only.  (Any transformations on the input should be done
--   before Rosie is called.)  Another design point is that the Rosie matching vm is
--   byte-oriented, with no knowledge of character encodings.  Keeping the vm simple allows for
--   many optimizations, only some of which are already implemented.  The simplicity of the vm
--   front-loads some of the matching effort onto the RPL compiler, of course.
-- 
--   For example, Rosie does case-insensitive matching by transforming characters in the pattern
--   into choices between their lower- and upper-case variants.  In the age of the Unicode
--   standard, in which case mappings may be complex, case-folding both the input and the pattern
--   would be costly (whereas it was easy for ASCII).  Also, the use cases for Rosie are not known
--   to include case-insensitive searching for long literal strings.  Therefore, the current
--   approach appears to be reasonable.  Time will tell.
-- 
--   But what to do about normalization?  Given the current Rosie implementation, two approaches
--   are apparent:
--   (1) Transform the input into a normalized form of choice, and write patterns accordingly; or
--   (2) Automatically transform string and character literals into an RPL choice between their
--       given form and equivalent forms (under the normalization forms deemed relevant).
--   The second approach is the one Rosie uses today for case-insensitive matching, so it should
--   be straightforward to adapt it to character equivalence.  Of course, there is more than one
--   kind of equivalence (under 4 different normalizations), and we currently lack information
--   about which are important to Rosie users.



-- TO DO:
--
-- GENERALIZE: Most of this code will work for all the UCD properties files.
-- OPTIMIZE: Adjacent ranges can sometimes be combined.
-- DERIVE the union classes L, M, N, S, P, Z, and C


local list = require "list"
local map = list.map

local codepoint = lpeg.R("09", "AF")^4		    -- 4 or more hex digits
local scripts_codepoints = lpeg.Ct(lpeg.C(codepoint) * (lpeg.P("..") * lpeg.C(codepoint))^-1)
local scripts_property = lpeg.C((lpeg.P(1)-lpeg.S(" ;#"))^1)
local property_peg = scripts_codepoints * lpeg.S(" ")^0 * lpeg.S(";") * lpeg.S(" ")^0 * scripts_property

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

function test_all_codepoints_against_all_values(value_patterns, value_ranges)
   local j=0
   for prop_name, prop_pattern in pairs(value_patterns) do
      io.write("Testing value: " .. prop_name .. " ")
      local n_chars, n_ok, n_fail =
	 test_all_codepoints_against_value(prop_name, prop_pattern, value_ranges[prop_name])
      j = j+1
      assert(n_chars == (n_ok + n_fail), "totals don't add up")
      io.write(tostring(n_chars), " characters tested, ", tostring(n_fail), " failures\n")      
   end -- for each property
   io.write(tostring(j), " values tested\n")
end
   
local codepoint_min = 0x0
local codepoint_max = 0x10FFFF

function test_all_codepoints_against_value(name, pattern, ranges)
   -- ranges is expected to be the ground truth.  we are testing the generated pattern.
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

function print_value_names(value_ranges, property_name)
   local i = 0
   for k,_ in pairs(value_ranges) do i = i+1; print(k); end
   print(i, property_name .. " values found")
end

assert(ROSIE_HOME)
ranges = {}
patterns = {}

function process_ucd_file(property_name)
   local filename = ROSIE_HOME .. "/src/unicode/UCD-10.0.0/" .. property_name .. ".txt"
   ranges[property_name] = read_ucd_property_file(filename)
   print_value_names(ranges[property_name], property_name)
   patterns[property_name] = compile_all_ranges(ranges[property_name])
end

function test_property(property_name)
   print("Testing property: " .. property_name)
   test_all_codepoints_against_all_values(patterns[property_name], ranges[property_name])
end

run() -- from ucd.lua
ranges["Category"] = general_category_ranges
patterns["Category"] = general_category_patterns

process_ucd_file("Scripts")
process_ucd_file("DerivedCoreProperties")
process_ucd_file("Blocks")
process_ucd_file("PropList")
--process_ucd_file("ScriptExtensions")


for name, _ in pairs(patterns) do
   test_property(name)
end
