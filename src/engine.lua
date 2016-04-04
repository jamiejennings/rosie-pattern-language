---- -*- Mode: Lua; -*- 
----
---- engine.lua    The RPL matching engine
----
---- (c) 2015, Jamie A. Jennings
----

-- TO DO:
--
-- Decide how to encode the capabilities that are othogonal to matching, like enumeration and
-- transformation.  The compiler needs to take two passes.  There are two problems to solve:
-- (1) Normal "production" mode:
--     Compile Cmt invocations into the peg that we will use for mapping, so that transformation
--     and other hooks will be called during matching.  Should keep these hooks somewhere
--     accessible, so that in interactive use, changes can be made to them without needing to
--     produce a new peg (i.e. without recompiling the source).  Trace is a good example of
--     something that may be added interactively, post-compilation.  WHERE TO STORE HOOKS?
-- (2) In debug/eval mode, today we walk the ast that was originally used to compile the peg.  One
--     approach is to tag ast nodes with transformation and other operations, and call them as we
--     eval. Hmmm... we are solving the same open question as in normal production mode, which is
--     where to store the hooks?  Looks like the answer is the ast.
--
-- 
-- Change the program from an instruction list to an AST.  The PC then becomes a pointer into that
-- AST, which starts at the root.  There are then several ways to run the engine:
--   (1) normal "match" operation, which uses the peg at the PC node
--   (2) debugging "step" operation, which uses eval on the PC node and stops at breakpoints in the AST
--
--
--
-- Add the multi-line operator.
--

local compile = require "compile"

----------------------------------------------------------------------------------------
-- Engine
----------------------------------------------------------------------------------------
-- A matching engine is a Lua object that has state as follows:
--   PatternProgram: the pattern being used right now, which is like a stored program
--   PC: a pointer into the pattern for the next instruction to be executed
--   Env: environment of defined patterns
--   Input: an input string
--   Source: describes the input, using a source string and a line number
--   Pos: the position in the input at which to start matching
--   Captures: the match results captured so far
--   State: MATCH and FAIL are final and idempotent, RUNNABLE means can run more
--
--    PatternProgram := {peg | readline | break}*
--    * when the engine reaches the end of the pattern, a match is returned.
--    * when the engine reaches a readline operation, it returns a readline continuation.
--    * when the engine reaches a break operation, it returns a breakpoint continuation.
--    Continuation := type, PC (index into pattern), position (index into input), captures

local compile = require "compile"
local recordtype = require("recordtype")
local unspecified = recordtype.unspecified;

engine = 
   recordtype.define(
   {  name=unspecified;				    -- for reference, debugging
      program=false;
      PC=false;
      input=false;
      pos=false;
      env=false;
      captures=false;
      source=unspecified;		     -- string describing the input source
      line=false;			     -- integer, where 'input' is at this line in 'source'
      --
      run=function(...) error("Engine not initialized"); end;
      state="NOINPUT";				    -- "FAIL", "MATCH", "RUNNABLE", "NOINPUT"
  },
   "engine"
)

local locale = lpeg.locale()

-- Run:
-- With no additional arguments, 'run' continues the engine's program.
-- With new_input (and optionally other args), the PC reset to 1 and the program started again.
local function run_engine(e, new_input, new_pos, new_source, new_line)
   if new_input then
      new_pos = new_pos or 1
      new_source = new_source or tostring(unspecified);
      new_line = new_line or 1

      e.input = new_input;
      e.pos = new_pos;
      e.source = new_source;
      e.line = new_line;
      e.captures = {}
      e.PC = 1
      e.state="RUNNABLE"
   end

   if e.state=="NOINPUT" then
      error(string.format("Engine %s: entered without any input", e.name))
   end

--   assert(type(e.input)=="string", "Engine input not a string: "..tostring(e.input))
--   assert(type(e.pos)=="number")
--   assert(type(e.source)=="string")
--   assert(type(e.line)=="number")

   if not (type(e.program)=="table" and e.program[1]) then
      error(string.format("Engine %s: no program", e.name))
   end

   local instruction, newcaps, newpos
   while true do
      if e.state~="RUNNABLE" then break; end;
      instruction = e.program[e.PC]
      e.PC = e.PC + 1
      if not instruction then
	 -- at end of program
	 e.state = "MATCH"
	 break;
      elseif pattern.is(instruction) then
	 newcaps, newpos = compile.match_peg(instruction.peg, e.input, e.pos)
	 if type(newcaps)=="table" then
	    table.insert(e.captures, newcaps)
	    e.pos = newpos
	 else
	    -- fail
	    e.state = "FAIL"
	    break;
	 end
      elseif instruction=="break" then
	 break;
      else
	 error(string.format("Engine %s: unknown opcode in program: %s ",
			     e.name, tostring(e.program[PC])))
      end -- switch on instruction type
   end -- while true

   -- !@# FIXME:
   -- Here we need to merge (reduce) the individual captures in e.captures into a single result.
   -- But what to do if the capture name (its primary index) is not the same across all the
   -- captures, as a result of having different patterns at various points in e.program?
   return e.captures[1], e.pos, e.state
end

engine.create_function =
   function(_new, name, initial_env)
      return _new{name=name, program={}, PC=1, env=initial_env, run=run_engine}
   end

----------------------------------------------------------------------------------------
-- Matching functions using engines
----------------------------------------------------------------------------------------

function match(expression_source, input, start, en)
   assert(type(expression_source)=="string", "Pattern expression is not a string: "..tostring(expression_source))
   assert(engine.is(en))
   local pat = compile.compile_command_line_expression(expression_source, en.env)
   if not pat then return nil; end		    -- compiler already printed error info
   en.program = {pat}
   local m, pos, state = en:run(input, start)
   return m, pos
end


----------------------------------------------------------------------------------------
-- The functions below are used in run.lua to process input files
----------------------------------------------------------------------------------------

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

-- A "finder peg" searches in a string for the first match of peg.  This should be implemented as
-- a macro (transformation on ASTs) at some point.
function peg_to_finder_peg(peg)
   return lpeg.P(1 - peg)^0 * peg
end

function grep_match_compile_to_peg(exp_source, env)
   local peg = compile.compile_command_line_expression(exp_source, env, false) -- NOT using raw mode
   if peg then 
      return peg.peg and peg_to_finder_peg(peg.peg)
   else
      return nil
   end
end

