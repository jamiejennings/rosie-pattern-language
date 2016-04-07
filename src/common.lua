---- -*- Mode: Lua; -*- 
----
---- common.lua        Functions common to many parts of Rosie
----
---- (c) 2015, Jamie A. Jennings
----

----------------------------------------------------------------------------------------
-- NOTE: The reason that this set of common functions exists is that Rosie's internal
-- AST now has the same structure as the Rosie output (a match).  So, AST functions
-- are now match functions, and vice versa.
----------------------------------------------------------------------------------------

lpeg = require "lpeg"
recordtype = require "recordtype"
local unspecified = recordtype.unspecified
local Cc, Cg, Ct, Cp, C = lpeg.Cc, lpeg.Cg, lpeg.Ct, lpeg.Cp, lpeg.C

local common = {}				    -- interface

assert(ROSIE_HOME, "The variable ROSIE_HOME is not set in common.lua")

function common.compute_full_path(path)
   local full_path
   if path:sub(1,1)=="." or path:sub(1,1)=="/" then -- WILL BREAK ON WINDOWS
      -- absolute path or relative to current directory
      full_path = path
   else
      -- construct a path relative to ROSIE_HOME
      full_path = ROSIE_HOME .. "/" .. path
   end
   full_path = full_path:gsub("\\ ", " ")	    -- unescape a space in the name
   return full_path
end

----------------------------------------------------------------------------------------
-- AST functions
----------------------------------------------------------------------------------------

-- Note: walk_ast is a function to traverse a parse tree.  One can call it with auxiliary
-- functions in order to do things like:
-- (1) Reveal the contents of the tree, i.e. generate the program the way the parser saw it
-- (2) Compile the program
-- (3) Eval interactively, so we can see where there are failures in pattern matching
--     The idea is that the match function is called with an expression.  If the match fails, then
--     the user invokes match again with debug turned on, and can then see how the matcher
--     actually worked.  In this mode, each pattern is compiled just in time.

function common.walk_ast(a, functions, ...)
   assert(type(a)=="table", "walk_ast: first argument not an ast "..tostring(a))
   assert(type(a[1])~="table", "walk_ast first argument not an ast (maybe it's a list of ast's?): "..tostring(a))
   assert(type(functions)=="table")
   local name, pos, text, subs, subidx = common.decode_match(a)
   local f = functions[name]
   if not f then f = functions.default; end
   if not f then
      if functions[1] then			    -- name of caller for debugging
	 error("walk_ast called by "..functions[1]
	       ..": missing function to handle ast node type: " .. tostring(name))
      else
	 error("walk_ast: missing function to handle ast node type: " .. tostring(name))
      end
   end
   return f(a, ...)
end

----------------------------------------------------------------------------------------
-- Matches
----------------------------------------------------------------------------------------
-- Matches are the data structure of the ASTs produced by the parser,
-- as well as the data structures produced by matching rpl expressions.

-- Wrap a peg such that the resulting peg creates a match (AST) node that has this form:
-- {name = {text=<string>, pos=<int>}}
-- E.g.
--    [*: 
--     [text: "Hello", 
--      pos: 1]]

local function create_match(name, pos, capture, ...)
   local t = {};
   t.pos = pos;
   t.text=capture;
   t.subs = {...}
   return {[name]=t};
end

function common.match_node_wrap(peg, name)
   return (Cc(name) * Cp() * peg) / create_match
end

-- return the match name, source position, match text, and (if there are subs), the table with the
-- subs and the index of first sub.  (because there used to be other things in the sub table)

function common.decode_match(t)
   local name, rest = next(t)
   return name, rest.pos, rest.text, rest.subs[1] and rest.subs, rest.subs[1] and 1
end

-- verify that a match has the correct structure
function common.verify_match(t)
   assert(type(t)=="table", "Match is not a table")
   local name, pos, text, subs, subidx = decode_match(t)
   assert(type(name)=="string", "Match name is not a string: "..tostring(name))
   assert(type(text)=="string", "Match text is not a string: "..tostring(text).." in match name: "..name)
   assert(type(pos)=="number", "Match position is not a number: "..tostring(pos).." in match name: "..name)
   if subidx then
      for i = subidx, #subs do
	 local v = subs[subidx]
	 assert(type(v)=="table", "Sub match is not a table: "..tostring(v).." in match name: "..name)
	 assert(verify_match(v))
      end
   end
   return true
end

function common.compare_matches(t1, t2)
   local function check_pos_mismatch(p1, p2)
      if p ~= p2 then
	 print("Warning: pos fields don't match ("
	       .. tostring(p1) .. "," .. tostring(p2) .. ")")
      end
   end
   local name1, pos1, text1, subs1, subidx1 = common.decode_match(t1)
   local name2, pos2, text2, subs2, subidx2 = common.decode_match(t2)
   if name1 == name2
      and text1 == text2
      and subidx1 == subidx2
   then
      if subidx1 then
	 -- subs exist
	 local mismatch = false;
	 for i = subidx1, #subs1 do
	    local ok, m1, m2 = common.compare_matches(subs1[i], subs2[i])
	    if not ok then
	       mismatch = i
	       break;
	    end
	 end -- for each sub-match
	 if mismatch then
	    return false, m1, m2
	 else
	    check_pos_mismatch(pos1, pos2)
	    return true
	 end
      else
	 -- no subs
	 check_pos_mismatch(pos1, pos2)
	 return true
      end
   else
      -- one of the values didn't match
      return false, t1, t2
   end
end
      

----------------------------------------------------------------------------------------
-- Pattern definition
----------------------------------------------------------------------------------------

pattern = 
   recordtype.define(
   {  name=unspecified;			 -- for reference, debugging
      peg=unspecified;			 -- lpeg pattern
      alternates=false;			 -- array of 2 lpeg patterns that make up a choice pattern
      alias=false;			 -- is this an alias or not
      ast=false;			 -- ast that generated this pattern, for pattern debugging
--      source=unspecified;		 -- source (filename, maybe line also?)
--      uuid=unspecified;
  },
   "pattern"
)

function common.reconstitute_pattern_definition(id, p)
   if p then
      return ((p.alias and "alias ") or "") .. id .. " = " .. ((p.ast and
								parse.reveal_ast(p.ast)) or
							    "// built-in RPL pattern //") 
   else
      return "undefined identifier: " .. id
   end
end

return common
