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

local left_delim = utf8.char(0x300A)
local right_delim = utf8.char(0x300B)

local node_marker_string = utf8.char(0x251c) .. utf8.char(0x2500) .. utf8.char(0x2500) .. " "
local last_node_marker_string = utf8.char(0x2514) .. utf8.char(0x2500) .. utf8.char(0x2500) .. " "
local node_marker_len = utf8.len(node_marker_string)
assert(utf8.len(last_node_marker_string) == node_marker_len)

local tab_string = string.rep(" ", node_marker_len-1)
local vertical_bar = utf8.char(0x2502)

local function node_marker(is_last_node)
   if is_last_node == nil then return ""
   else return (is_last_node and last_node_marker_string or node_marker_string)
   end
end

local function tab(is_last_node)
   if is_last_node == nil then return ""
   else return (is_last_node and " " or vertical_bar) .. tab_string
   end
end

-- TODO:
-- + Include in the trace ALL the components of a sequence/choice
-- + Draw the tree using codepoints 2500-257F
-- - Compress a sequence of simple charset matches to one trace entry
-- - Print a statement about leftover characters after the tree
-- 
-- + Show the "best guess" as to what went wrong by focusing on the path in the trace (tree) that
--   went the furthest in the input.  (This is a heuristic.)
-- 
-- - Maybe add color to highlight where branches fail?
-- 
-- - Show sequences different from branching due to choices
-- 
-- - Make this [below] convention a configuration option with display settings like:
--   "none" - output the bytes in the input as-is
--   "hex" - translate each byte into its 2-char hex representation
--   "ascii" - translate 0-31 to ^@^A-^Z^[^\^]^^^_ and 127-255 into \x##
--   "utf8" - translate as follows
--                          utf8               utf8     
--     CHAR                 GLYPH              CODEPOINT    
--     Space                dot                U+00B7       
--     Tab                  right arrow        U+2192       
--     Newline              down arrow         U+2193
--     Return               solid bent arrow   U+21B5
--     Other whitespace     white dot          U+25E6 
--     Other non-printable  white box          U+25A1


-- 'node_tostrings' returns a table of strings, one per line of output.  The first time it is
-- called, the is_last_node argument should be nil.  Subsequent (recursive) calls will supply a
-- boolean value.

local function one_node_tostrings(t, is_last_node)
   local lines = { node_marker(is_last_node) .. "Expression: " .. ast.tostring(t.ast) }
   table.insert(lines,
		tab(is_last_node) .. "Looking at: " .. left_delim .. t.input:sub(t.start) ..
	        right_delim .. " (input pos = " .. tostring(t.start) .. ")")
   if t.match then
      table.insert(lines, tab(is_last_node) .. "Matched " .. tostring(t.nextpos - t.start) .. " chars")
   elseif t.match == false then
      table.insert(lines, tab(is_last_node) .. "No match")
   else
      assert(t.match==nil)
      table.insert(lines, tab(is_last_node) .. "Not attempted")
   end
   return lines
end

local function select_subs_to_show(node, sub_on_path)
   assert(node.ast)
   if not sub_on_path then
      -- If we are not following a path, then we are showing the entire tree
      return node.subs or {}
   end
   local subs = list.new()
   if (not node.subs) or not list.member(sub_on_path, list.from(node.subs)) then
      -- Trace trees are fuller than ASTs, i.e. they have sub-traces where identifiers are
      -- referenced and where quantified expressions are unrolled.  So there are times when we
      -- show a node but not its subs because the path did not include one of the subs.
      return subs
   elseif ast.sequence.is(node.ast) or ast.choice.is(node.ast) then
      local i = 1
      while node.subs[i] and (node.subs[i].match ~= nil) do
	 table.insert(subs, node.subs[i])	    -- FUTURE: write list.insert?
	 i = i+1
      end
      return subs
   else
      return list.new(sub_on_path)
   end
end

local function node_tostrings(t, is_last_node, path)
   local lines = one_node_tostrings(t, is_last_node)
   local sublines = {}
   if path and list.null(path) then
      return lines
   end
   local subs_to_show = select_subs_to_show(t, path and list.car(path))
   local next_path = path and list.cdr(path)
   local last = #subs_to_show
   for i = 1, last do
      local onesublines = node_tostrings(subs_to_show[i], (i==last), next_path)
      table.move(onesublines, 1, #onesublines, #sublines+1, sublines)      
   end
   for i = 1, #sublines do
      if is_last_node ~= nil then
	 sublines[i] = tab(is_last_node) .. sublines[i]
      end
   end
   table.move(sublines, 1, #sublines, #lines+1, lines)      
   return lines
end

function trace.tostring(t)
   assert(t.ast)
   local lines = node_tostrings(t)
   return table.concat(lines, "\n")
end
      
-- Return the trace leaf that has the larger value of nextpos, i.e. the leaf that consumed more of
-- the input string.  
local function better_of(leaf1, leaf2)
   assert((not leaf2) or leaf2.nextpos)
   if (leaf1 and
       leaf1.nextpos and
       ((not leaf2) or (leaf1.nextpos > leaf2.nextpos))) then
      return leaf1
   end
   return leaf2
end

-- When a match fails, all of the leaves in the trace tree will indicate a match failure.  We
-- cannot be sure about which path through the tree is the one that the user *thought* would match
-- the input, but we can guess.  A reasonable guess is the path from the root to the leaf that
-- consumed the most input characters.  In the case of a tie, we will choose the path we encounter
-- first. 
local function max_input_path(t, max_node)
   if t.subs then
      for _, sub in ipairs(t.subs) do
	 local local_max = max_input_path(sub)
	 max_node = better_of(local_max, max_node)
	 sub.parent = t				    -- establish a path going UP the tree
      end
      return max_node
   else
      -- no subs, so t is a leaf node
      return better_of(t, max_node) 
   end
end

local function trim_matches(path)
   local last_match_index = 1
   for i = #path, 2, -1 do
      if not path[i].match then break; end
      last_match_index = i
   end
   for i = last_match_index + 1, #path do
      path[i] = nil
   end
   return path
end

function trace.max_path(t)
   local leaf = max_input_path(t)
   local path = list.new(leaf)
   while leaf.parent do
      path = list.cons(leaf.parent, path)
      leaf = leaf.parent
   end
   return trim_matches(path)
end

function trace.path_tostring(p)
   assert(p and p[1] and p[1].ast)
   local lines = node_tostrings(list.car(p), nil, list.cdr(p))
   return table.concat(lines, "\n")
end

---------------------------------------------------------------------------------------------------
-- Trace functions for each expression type
---------------------------------------------------------------------------------------------------

local expression;

-- Append to 'matches' a trace record for each item in 'exps' that we didn't even try to match,
-- which are those beginning at index 'start'.
local function append_unattempted(exps, start, matches, input, nextstart)
   for i = start, #exps do
      table.insert(matches, {ast=exps[i], input=input, start=nextstart})
   end
end

local function sequence(e, a, input, start, expected, nextpos)
   local matches = {}
   local nextstart = start
   for _, exp in ipairs(a.exps) do
      local result = expression(e, exp, input, nextstart)
      table.insert(matches, result)
      if not result.match then break
      else nextstart = result.nextpos; end
   end -- for
   local n = #matches
   if n < #a.exps then
      append_unattempted(a.exps, n+1, matches, input, nextstart)
   end
   if (n==#a.exps) and (matches[n].match) then
      assert(expected, "sequence match differs from expected")
      assert(matches[n].nextpos==nextpos, "sequence nextpos differs from expected")
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
   local n = #matches
   if n < #a.exps then
      append_unattempted(a.exps, n+1, matches, input, matches[n].nextpos)
   end
   if matches[n].match then
      assert(expected, "choice match differs from expected")
      assert(matches[n].nextpos==nextpos, "choice nextpos differs from expected")
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
   if not m then m = false; end
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


