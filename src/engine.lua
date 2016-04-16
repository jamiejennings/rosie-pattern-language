---- -*- Mode: Lua; -*-                                                                           
----
---- engine.lua    The RPL matching engine
----
---- © Copyright IBM Corporation 2016.
---- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
---- AUTHOR: Jamie A. Jennings


----------------------------------------------------------------------------------------
-- Engine
----------------------------------------------------------------------------------------
-- A matching engine is a Lua object that has state as follows:
--   env: environment of defined patterns
--   program: the pattern being matched (in earlier versions, this was a multi-step program)
--   id: a string meant to be a unique identifier (currently unique in the Lua state)

local compile = require "compile"
local recordtype = require("recordtype")
local unspecified = recordtype.unspecified;

engine = 
   recordtype.define(
   {  name=unspecified;				    -- for reference, debugging
      env=false;
      program=false;
      id=unspecified;
      --
      match=false;
      match_using_exp=false;
  },
   "engine"
)

engine.tostring_function = function(orig, e)
			      return '<engine: '..tostring(e.name)..' ('.. e.id ..')>'; end

-- This used to work.  Maybe should put this capability back into recordtypes?
--
--    engine.set_slot_function = 
--       function(set_slot, self, slot, value)
--          if slot=="program" then
--             if not pattern.is(value) then
--                error("Invalid engine program: " .. tostring(value)) 
--             end
--             set_slot(self, slot, value)
--          else -- switch on slot name
--             error('Cannot set this engine property: ' .. slot)
--          end
--       end
--

local locale = lpeg.locale()

--local function engine_set_program(e, pat)
--   -- for now, a program is a list of one pattern (earlier versions had more...)
--   if not pattern.is(pat) then error("Invalid program: " .. tostring(pat)); end
--   e.program = { pat }
--   return true
--end

-- match(input_text, start)
-- Using the stored program, run it against the input, starting at position start.

local function identity_function(...) return ...; end

local function engine_match(e, input, start, encode)
   start = start or 1
   encode = encode or identity_function
   if not e.program then
      error(string.format("Engine %s (%s): no program", e.name, e.id))
   end
   local instruction = e.program[1]
   local result, nextpos = compile.match_peg(instruction.peg, input, start)
   return encode(result), nextpos
end

local function engine_match_using_exp(e, exp, input, start, encode)
   start = start or 1
   encode = encode or identity_function
   local pat, msg = compile.compile_command_line_expression(exp, e.env)
   if not pat then error(msg,0); end
   local result, nextpos = compile.match_peg(pat.peg, input)
   return encode(result), nextpos
end

engine.create_function =
   function(_new, name, initial_env)
      initial_env = initial_env or compile.new_env()
      -- assigning a unique instance id should be part of the recordtype module
      local id = tostring({}):match("0x(.*)") or "id/err"
      return _new{name=name,
		  env=initial_env,
		  id=id,
		  match=engine_match,
		  match_using_exp=engine_match_using_exp}
   end

----------------------------------------------------------------------------------------
-- The functions below are used in run.lua to process input files
----------------------------------------------------------------------------------------

-- return a flat list of matches
--    function grep_match_peg(peg, input, first_only)
--       -- search for first occurrence
--       local len = #input
--       local results = {}
--       local result
--       local pos = 1
--       local prev = 1
--       peg = peg * lpeg.Cp()
--
--       -- Note on looping:
--       -- It's possible for a pattern to match the empty string, and so we can get to a state where
--       -- that is the only match, even though there is still non-matching input left.  Since an empty
--       -- match consumes nothing, the pos will remain the same.  We look for when pos does not
--       -- advance, and end the loop.
--
--       while true do
--          result, pos = peg:match(input, prev)      -- result is one match or none
--          if pos then table.insert(results, result); end
--          if (not pos) or                           -- no more matches
--             (pos > len) or                         -- ran out of input
--             (pos == prev) or               -- looping (see below)
--             first_only                     -- only want first result
--          then return results; end
--          prev = pos
--       end -- while
--    end

--    -- A "finder peg" searches in a string for the first match of peg.  This should be implemented as
--    -- a macro (transformation on ASTs) at some point.
--    function peg_to_finder_peg(peg)
--       return lpeg.P(1 - peg)^0 * peg
--    end
--
--    function grep_match_compile_to_peg(exp_source, env)
--       local peg = compile.compile_command_line_expression(exp_source, env, false) -- NOT using raw mode
--       if peg then 
--          return peg.peg and peg_to_finder_peg(peg.peg)
--       else
--          return nil
--       end
--    end

