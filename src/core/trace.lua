-- -*- Mode: Lua; -*-                                                                             
--
-- trace.lua
--
-- © Copyright IBM Corporation 2017.
-- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
-- AUTHOR: Jamie A. Jennings


local ast = require "ast"
local common = require "common"
local pattern = common.pattern
local rmatch = common.rmatch

local trace = {}

---------------------------------------------------------------------------------------------------
-- Print a trace
---------------------------------------------------------------------------------------------------

local function tab(n)
   return string.rep(" ", n)
end

function trace.tostring(t, indent)
   indent = indent or 0
   local delta = 2
   assert(t.ast)
   local str = tab(indent) .. "Expression: " .. ast.tostring(t.ast) .. "\n"
   indent = indent + 2
   str = str .. tab(indent) .. "Looking at: |" .. t.input:sub(t.start) .. "| (input pos = "
   str = str .. tostring(t.start) .. ")\n"
   str = str .. tab(indent)
   if t.match then
      str = str .. "Matched " .. tostring(t.nextpos - t.start) .. " chars"
   else
      str = str .. "No match"
   end
   str = str .. "\n"
   for _, sub in ipairs(t.subs or {}) do
      str = str .. trace.tostring(sub, indent+delta)
   end
   return str
end
      
---------------------------------------------------------------------------------------------------
-- Trace functions for each expression type
---------------------------------------------------------------------------------------------------

local expression;

local function sequence(e, a, input, start, expected, nextpos)
   local matches = {}
   local nextstart = start
   for _, exp in ipairs(a.exps) do
      local result = expression(e, exp, input, nextstart)
      table.insert(matches, result)
      if not result.match then break
      else nextstart = result.nextpos; end
   end -- for
   if (#matches==#a.exps) and (matches[#matches].match) then
      assert(expected, "sequence match differs from expected")
      local last = matches[#matches]
      assert(last.nextpos==nextpos, "sequence nextpos differs from expected")
      return {match=expected, nextpos=nextpos, ast=a, subs=matches, input=input, start=start}
   else
      assert(not expected, "sequence non-match differs from expected")
      return {match=expected, nextpos=nextpos, ast=a, subs=matches, input=input, start=start}
   end
end

local function choice(e, a, input, start, expected, nextpos)
   local matches = {}
   for _, exp in ipairs(a.exps) do
      local result = expression(e, exp, input, start)
      table.insert(matches, result)
      if result.match then break; end
   end -- for
   local last = matches[#matches]
   if (last.match) then
      assert(expected, "choice match differs from expected")
      assert(last.nextpos==nextpos, "choice nextpos differs from expected")
      return {match=expected, nextpos=nextpos, ast=a, subs=matches, input=input, start=start}
   else
      assert(not expected, "choice non-match differs from expected")
      return {match=expected, nextpos=nextpos, ast=a, subs=matches, input=input, start=start}
   end
end

-- FUTURE: A qualified reference to a separately compiled module may not have an AST available
-- for debugging (unless it was compiled with debugging enabled).

-- N.B. Currently, when the AST field of a pattern is false, the pattern is a built-in.
local function ref(e, a, input, start, expected, nextpos)
   local pat = a.pat
   if not pat.ast then
      -- In a trace, a reference has one sub (or none, if it is built-in)
      return {match=expected, nextpos=nextpos, ast=a, input=input, start=start}
   else
      local result = expression(e, pat.ast, input, start)
      if expected then
	 assert(result.match, "reference match differs from expected")
	 assert(nextpos==result.nextpos, "reference nextpos differs from expected")
      else
	 assert(not result.match)
      end
      -- In a trace, a reference has one sub (or none, if it is built-in)
      return {match=expected, nextpos=nextpos, ast=a, subs={result}, input=input, start=start}
   end
end

-- Note: 'atleast' implements * when a.min==0
local function atleast(e, a, input, start, expected, nextpos)
   local matches = {}
   local nextstart = start
   assert(type(a.min)=="number")
   while true do
      local result = expression(e, a.exp, input, nextstart)
      table.insert(matches, result)
      if not result.match then break
      else nextstart = result.nextpos; end
   end -- while
   local last = matches[#matches]
   if (#matches > a.min) or (#matches==a.min and last.match) then
      assert(expected, "atleast match differs from expected")
      assert(nextstart==nextpos, "atleast nextpos differs from expected")
      return {match=expected, nextpos=nextpos, ast=a, subs=matches, input=input, start=start}
   else
      assert(not expected, "atleast non-match differs from expected")
      return {match=expected, nextpos=nextpos, ast=a, subs=matches, input=input, start=start}
   end
end

-- 'atmost' always succeeds, because it matches from 0 to a.max copies of exp, and it stops trying
-- to match after it matches a.max times.
local function atmost(e, a, input, start, expected, nextpos)
   local matches = {}
   local nextstart = start
   assert(type(a.max)=="number")
   for i = 1, a.max do
      local result = expression(e, a.exp, input, nextstart)
      table.insert(matches, result)
      if not result.match then break
      else nextstart = result.nextpos; end
   end -- while
   local last = matches[#matches]
   assert(expected, "atmost match differs from expected")
   if last.match then
      assert(last.nextpos==nextpos, "atmost nextpos differs from expected")
   end
   return {match=expected, nextpos=nextpos, ast=a, subs=matches, input=input, start=start}
end

local function cs_simple(e, a, input, start, expected, nextpos, complement)
   local simple = a.pat
   assert(pattern.is(simple))
   local wrapped_peg = common.match_node_wrap(simple.peg, "*")
   local m, nextstart = rmatch(wrapped_peg, input, start)
   if (m and (not complement)) or ((not m) and complement) then
      assert(expected, "simple character set match differs from expected")
      if m then
	 assert(nextstart==nextpos, "simple character set nextpos differs from expected")
      end
   else
      assert(not expected, "simple character set non-match differs from expected")
   end
   return {match=expected, nextpos=nextpos, ast=a, input=input, start=start}
end

local function cs_exp(e, a, input, start, expected, nextpos)
   if ast.simple_charset_p(a) then
      return cs_simple(e, a, input, start, expected, nextpos, false)
   elseif ast.cs_exp.is(a.cexp) then
      local result = cs_exp(e, a.exp, input, nextstart)
      if (result.match and (not a.complement)) or ((not result.match) and a.complement) then
	 assert(expected, "cs_exp match differs from expected")
	 if result.match then
	    assert(nextstart==nextpos, "cs_exp nextpos differs from expected")
	 end
      else
	 assert(not expected, "cs_exp non-match differs from expected")
      end
      return {match=expected, nextpos=nextpos, ast=a, subs={result}, input=input, start=start}
   elseif ast.cs_union.is(a.cexp) then
      -- This is identical to 'choice' except for a.cexps, cs_exp, and the assert messages.
      -- Should re-factor, unless there's a reason to treat union/choice differently?
      local matches = {}
      for _, exp in ipairs(a.cexp.cexps) do
	 local result = cs_exp(e, exp, input, start)
	 table.insert(matches, result)
	 if result.match then break; end
      end -- for
      local last = matches[#matches]
      if (last.match and (not a.complement)) or ((not last.match) and a.complement) then
	 assert(expected, "cs_union match differs from expected")
	 if last.match then
	    assert(last.nextpos==nextpos, "cs_union nextpos differs from expected")
	 end
      else
	 assert(not expected, "cs_union non-match differs from expected")
      end
      return {match=expected, nextpos=nextpos, ast=a, subs=matches, input=input, start=start}
   elseif ast.cs_intersection.is(a.cexp) then
      throw("character set intersection is not implemented", a)
   elseif ast.cs_difference.is(a.cexp) then
      throw("character set difference is not implemented", a)
   else
      assert(false, "trace: unknown cexp inside cs_exp", a)
   end
end
      
local function predicate(e, a, input, start, expected, nextpos)
   local result = expression(e, a.exp, input, start)
   if (result.match and (a.type=="@")) or ((not result.match) and (a.type=="!")) then
      assert(expected, "predicate match differs from expected")
      -- Cannot compare nextpos to result.nextpos, because 'a.exp' is NOT a predicate (so it
      -- advances nextpos) whereas 'a' IS a predicate (which does not advance nextpos).
      assert(nextpos==start, "predicate was evaluated, but nextpos advanced ahead of start???")
   else
      assert(not expected,
	     "predicate non-match differs from expected: " .. ast.tostring(a) ..
	     " on input: " .. input:sub(start))
   end
   return {match=expected, nextpos=nextpos, ast=a, subs={result}, input=input, start=start}
end

local function grammar(e, a, input, start, expected, nextpos)
   -- FUTURE: Simulate a grammar using its pieces.  This will require some careful bouncing in and
   -- out of lpeg because we cannot attempt a match against an lpeg.V(rulename) peg.
   return {match=expected, nextpos=nextpos, ast=a, input=input, start=start}
end

function expression(e, a, input, start)
   local pat = a.pat
   assert(pattern.is(pat), "no pattern stored in ast node " .. tostring(a))
   local peg = common.match_node_wrap(pat.peg, "*")
   local ok, m, nextpos = pcall(rmatch, peg, input, start, 1)
   if not ok then
      print("\n\n\nTrace failed while working on: ", a)
      if a.exps then print("a.exps: " .. tostring(list.from(a.exps))); end
      print("ast.tostring(a) is: " .. ast.tostring(a))
      print("start is: " .. tostring(start) .. " and input is: |" ..  input .. "|")
      error("rmatch failed: " .. m)
   end
   if ast.literal.is(a) then
      return {match=m, nextpos=nextpos, ast=a, input=input, start=start}
   elseif ast.cs_exp.is(a) then
      return cs_exp(e, a, input, start, m, nextpos)
   elseif ast.simple_charset_p(a) then
      return cs_simple(e, a, input, start, m, nextpos, false)
   elseif ast.sequence.is(a) then
      return sequence(e, a, input, start, m, nextpos)
   elseif ast.choice.is(a) then
      return choice(e, a, input, start, m, nextpos)
   elseif ast.ref.is(a) then
      return ref(e, a, input, start, m, nextpos)
   elseif ast.atleast.is(a) then
      return atleast(e, a, input, start, m, nextpos)
   elseif ast.atmost.is(a) then
      return atmost(e, a, input, start, m, nextpos)
   elseif ast.predicate.is(a) then
      return predicate(e, a, input, start, m, nextpos)
   elseif ast.grammar.is(a) then
      return grammar(e, a, input, start, m, nextpos)
   else
      -- TODO: Change this to throw a proper error
      print("\nError:")
      print("Arguments to trace:", ast.tostring(a), a, start, m, nextpos)
      error("Internal error: invalid ast type in trace.expression: " .. tostring(a))
   end
end

function trace.expression(r, input, start)
   start = start or 1
   assert(type(input)=="string")
   assert(type(start)=="number")
   assert(r.pattern and r.engine)		    -- quack
   assert((pcall(rawget, r.pattern, "ast")))	    -- quack: "is ast a valid key in r.pattern?"
   local a = r.pattern.ast
   assert(a, "no ast stored for pattern")
   return expression(r.engine, a, input, start)
end

return trace


