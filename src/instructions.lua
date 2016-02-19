---- -*- Mode: Lua; -*- 
----
---- instructions.lua     Define the instructions that tell Rosie what to do
----
---- (c) 2015, Jamie A. Jennings
----

--- Instructions specify how to parse, what to annotate, what to sanitize, what to normalize, on
--- what to collect meta-data, and what/how to correlate.

--- Eventually, we will allow the user to specify instructions that include a pipeline, which is a
--- (mostly) arbitrary sequence of processing steps that can be done in a single pass of the input
--- data.  

-- TO DO:
-- 
-- Add an instruction to include a source identifier (e.g. filename+line number, or generate a
-- uuid)... or just do this anyway and let consumers throw it away if they don't care.
--
-- Can we remove the artifice of the "line" as a unit of input, and make it more abstract than
-- that?  Hmmm... but we want the output format to be a list of "records", each of which is a
-- sequence of  one or more semantic objects.
-- 
-- Proposal for instruction objects:
--   Patterns: map from raw input to semantic object
--   Transformations: map from semantic object to semantic object(s)
--      Sanitize (delete or encrypt)
--      Normalize (replace or insert additional computed value)
--      Discard
--   Correlations: processing directives
--      Multi-line conditions (when to process multiple lines as a single entry)
--      Indexes (map from correlated values to output record ids)
--   Meta-data collections: additional results, apart from list of semantic objects
--      Enumerate observed "categorical" values
--      Compute observed range of "numeric" values, including number of lines read and output
--        records written.
-- 
-- How to specify replacement values, e.g. 1 for January?  Is this a form of normalization?  YES!
-- 
-- How to annotate multiple captures in a single pattern?  Or should we force a single annotation
-- to emit a single captured value?  Some cases:
--   * Annotation produces a single value
--   * Annotation produces a record of values (fixed number, each is "named")
--   * Annotation produces an array of values (could be fixed or variable number, each is
--     undifferentiated from the others)
--   * Annotation produces a record or array in which some values are records or arrays.
-- 
-- Should we enforce building up annotations out of smaller annotations (instead of just using
-- patterns)?  Let's explore:
--   name fields could be used to explain how a compound annotation was built
--   patterns would be combined as they would be combined in any case
--   schemas could be combined to produce the schema for the compound annotation
--   keep flags could become an array to act as a filter for what to keep/discard ???
--   enumeration flags together suggest a collection of tuple-based values
--   range flags together suggest that min, max are tuples of (independent) values
--   data type hints could be combined like labels into schema-like structures
-- ** Place the data type hint with the label in the schema? **
--
-- For notation, could use an array of patterns to represent non-tokenized input, i.e. spaces
-- matter and will be explicit in the sequence.  
--
--   Some other ordered collection of patterns could represent processing of tokenized input,
--   where tokens are whitespace separated.   
--
--   Or maybe always use arrays for sequences, but use prefix notation to indicate where
--   tokenization should be suspended? 
--

print("-*-*-*- deprecated source file instructions.lua loaded -*-*-*-")

-- attribute basic.datetime_patterns color=blue

lpeg = require "lpeg"

require "utils"

transform = 
   recordtype.define(
   { name=unspecified;				    -- for reference, debugging
     pattern=unspecified;			    -- the source pattern
     func=unspecified;				    -- transformation function
  },
   "transform"
)

production =
   recordtype.define(
   { name=unspecified;				    -- for reference, debugging
     pattern=unspecified;			    -- the source pattern
     type=unspecified; 				    -- enumeration, range
  },
   "production"
)

local locale = lpeg.locale()

function match_compile_to_peg(expression_source, env, raw)
   local pat = compile_command_line_expression(expression_source, env, raw)
   if not pat then
      io.write("Match: pattern did not compile: ".. expression_source.."\n");
      return nil
   end
   return pat.peg
end

function match_peg(peg, input, start, env, raw)
   -- Add tolerance for leading whitespace
   -- FIXME:  If peg has leading whitespace, this change makes it FAIL!!!
   return (locale.space^0 * peg * lpeg.Cp()):match(input, start)
end

function match(expression_source, input, start, env, raw)
   assert(type(expression_source)=="string", "Expression to match not a string: "..tostring(expression_source))
   env = env or ENV
   local peg = match_compile_to_peg(expression_source, env, raw)
   if peg then
      return match_peg(peg, input, start, env, raw)
   else
      return nil
   end
end

-- return a flat list of matches
function grep_match_peg(peg, input, first_only)
   -- search for first occurrence
   local len = #input
   local results = {}
   local result
   local pos = 1
   local prev = 1
   peg = peg * lpeg.Cp()

   -- Note on looping:
   -- It's possible for a pattern to match the empty string, and so we can get to a state where
   -- that is the only match, even though there is still non-matching input left.  Since an empty
   -- match consumes nothing, the pos will remain the same.  We look for when pos does not
   -- advance, and end the loop.

   while true do
      result, pos = peg:match(input, prev)	    -- result is one match or none
      if pos then table.insert(results, result); end
      if (not pos) or			    -- no more matches
         (pos > len) or			    -- ran out of input
         (pos == prev) or		    -- looping (see below)
         first_only			    -- only want first result
      then return results; end
      prev = pos
   end -- while
end

-- a "finder peg" searches in a string for the first match of peg
function peg_to_finder_peg(peg)
   return lpeg.P(1 - peg)^0 * peg
end

-- Should really make this a real macro (an ast transformation)
--function exp_to_finder_exp(exp)
--   return "< < !"..exp.." .>* "..exp.." >"
--end   

function grep_match_compile_to_peg(exp_source)
   local env = ENV
   local peg = match_compile_to_peg(exp_source, env, false) -- NOT using raw mode
   return peg and peg_to_finder_peg(peg)
end

-- return a list of matches
function grep_match(exp_source, input, first_only)
   local peg = grep_match_compile_to_peg(exp_source)
   if not peg then
      error("Grep match: pattern did not compile: " .. exp_source)
   else
      return grep_match_peg(peg, input, first_only)
   end
end

-- Do this before using grep_match, in order to get the right set of patterns:
--    clear(); process_manifest(ROSIE_HOME.."/grep-manifest")

-- return a list of strings
function grep_match_strings(exp_source, input, first_only)
   local results = grep_match(exp_source, input, first_only)
   if not results then return nil; end       -- could have been an error earlier, or no results
   local strings = {}
   for _,v in ipairs(results) do
      local name, pos, text = decode_match(v)
      table.insert(strings, text);
   end
   return strings
end

