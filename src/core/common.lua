---- -*- Mode: Lua; -*-                                                                           
----
---- common.lua        Functions common to many parts of Rosie
----
---- © Copyright IBM Corporation 2016, 2017.
---- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
---- AUTHOR: Jamie A. Jennings

local lpeg = require "lpeg"
local Cc, Cg, Ct, Cp, C = lpeg.Cc, lpeg.Cg, lpeg.Ct, lpeg.Cp, lpeg.C
local util = require "util"
local recordtype = require "recordtype"

-- REMOVED os dependency in v1-tranche-2
--local os = require "os"

local common = {}				    -- interface

----------------------------------------------------------------------------------------
-- UTF-8 considerations
----------------------------------------------------------------------------------------
local b1_lead = lpeg.R(string.char(0x00)..string.char(0x7F))   -- ASCII (1 byte)
local b2_lead = lpeg.R(string.char(0xC0)..string.char(0xDF))
local b3_lead = lpeg.R(string.char(0xE0)..string.char(0xEF))
local b4_lead = lpeg.R(string.char(0xF0)..string.char(0xF7))
local b5_lead = lpeg.R(string.char(0xF8)..string.char(0xFB))
local b6_lead = lpeg.R(string.char(0xFC)..string.char(0xFD))
local c_byte = lpeg.R(string.char(0x80)..string.char(0xBF)) -- continuation byte

-- This is denoted \X in Perl, PCRE and some other regex
common.utf8_char_peg = b1_lead +
               (b2_lead * c_byte) +
	       (b3_lead * c_byte * c_byte) +
	       (b4_lead * c_byte * c_byte * c_byte) +
	       (b5_lead * c_byte * c_byte * c_byte * c_byte) +
	       (b6_lead * c_byte * c_byte * c_byte * c_byte * c_byte)

-- Examples:
-- > utf8_char_peg:match("A")
-- 2
-- > snowman = "\u{002603}"
-- > snowman
-- ☃
-- > utf8_char_peg:match(snowman)
-- 4
-- > face = "\u{1f600}"
-- > face
-- 😀
-- > utf8_char_peg:match(face)
-- 5
-- >
	    
common.dirsep = package.config:sub(1, (package.config:find("\n"))-1)
assert(#common.dirsep==1, "directory separator should be a forward or a backward slash")

function common.compute_full_path(path, manifest_path, home)
   -- return the full path, the dirname of the path, and the basename of the path
   local full_path
   if (type(path)~="string") or (path=="") then
      error("Internal error: bad path argument to compute_full_path: " .. tostring(path))
   end
   if path:sub(1,1)=="$" then
      local sym = path:match("$([^" .. common.dirsep .. "]*)")
      local rest = path:match("$[^" .. common.dirsep .. "]*(.*)")
      if sym=="sys" then
	 full_path = home .. rest
      elseif sym=="lib" then
	 if (type(manifest_path)~="string") or (manifest_path=="") then
	    return false, "Error: cannot reference $lib outside of a manifest file: " .. path
	 end
	 if (manifest_path:sub(-1,-1)==common.dirsep) then
	    manifest_path = manifest_path:sub(1,-2)
	 end
	 full_path = manifest_path .. rest
       --
       -- REMOVED the $(foo) syntax in v1-tranche-2
       --
      -- elseif (#sym>2) and (sym:sub(1,1)=="(") and (sym:sub(-1,-1)==")") then
      -- 	 local env_value = os.getenv(sym:sub(2,-2))
      -- 	 if (not env_value) or (env_value=="") then
      -- 	    return false, string.format("Environment variable %q not set", sym:sub(2,-2))
      -- 	 end
      -- 	 full_path = env_value .. rest
      else -- sym is not any of the valid things
	 return false, string.format("Invalid file path syntax: %s", path)
      end
   else -- path does NOT start with $
      full_path = path
   end
   full_path = (full_path:gsub("\\ ", " "))	    -- unescape any spaces in the name
   local proper_path, base_name, splits = util.split_path(full_path, common.dirsep)
   return full_path, proper_path, base_name
end

-- Always return a table, possibly empty
function common.compact_messages(tbl)
   if (not tbl) or (type(tbl)~="table") then tbl = {tbl}; end
   local only_strings = {}
   for _, msg in ipairs(tbl) do
      if msg then table.insert(only_strings, msg); end
   end
   return only_strings
end

common.escape_substitutions =			    -- characters that change when escaped are:
   setmetatable(
   { a = "\a";					    -- bell
     b = "\b";					    -- backspace
     f = "\f";					    -- formfeed
     n = "\n";					    -- newline
     r = "\r";					    -- return
     t = "\t";					    -- tab
     v = "\v"; 					    -- vertical tab
     ['\\'] = '\\';				    -- backslash
     ['"'] = '"';				    -- double quote
--     ["'"] = "'";				    -- single quote
  },
   {__index = function(self, key) return key end}   -- TEMP
   -- FUTURE:
   -- any other escaped characters are errors
   -- {__index = function(self, key) error("Invalid escape sequence: \\" .. key); end}
)

function common.unescape_string(s)
   -- the only escape character is \
   -- a literal backslash is obtained using \\
   return (string.gsub(s, '\\(.)', common.escape_substitutions))
end

function common.escape_string(s)
   return (string.format("%q", s)):sub(2,-2)
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
   assert(type(a)=="table", "walk_ast: first argument not an ast: "..tostring(a))
   assert(type(a[1])~="table", "walk_ast first argument not an ast (maybe it's a list of ast's?): "..tostring(a))
   assert(type(functions)=="table")
   local name, pos, text, subs = common.decode_match(a)
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
   t.subs = {...};
   if (not t.subs[1]) then t.subs=nil; end
   return {[name]=t};
end

common.create_match = lpeg.r_create_match
--common.create_match = create_match

function common.match_node_wrap(peg, name)
   return (Cc(name) * Cp() * C(peg)) / common.create_match
end

function common.rmatch(peg, input, start)
   return peg:match(input, start)
end

-- return the match name, source position, match text, and (if there are subs), the table with the
-- subs and the index of first sub.  (because there used to be other things in the sub table)

function common.decode_match(t)
   local name, rest = next(t)
   return name, rest.pos, rest.text, rest.subs
end

function common.subs(match)
   return (match[(next(match))].subs) or {}
end

function common.match_to_text(t)
   local name, rest = next(t)
   return rest.text
end

-- verify that a match has the correct structure
function common.verify_match(t)
   assert(type(t)=="table", "Match is not a table")
   local name, pos, text, subs = decode_match(t)
   assert(type(name)=="string", "Match name is not a string: "..tostring(name))
   assert(type(text)=="string", "Match text is not a string: "..tostring(text).." in match name: "..name)
   assert(type(pos)=="number", "Match position is not a number: "..tostring(pos).." in match name: "..name)
   if subs then
      for i = 1, #subs do
	 local v = subs[i]
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
   local name1, pos1, text1, subs1 = common.decode_match(t1)
   local name2, pos2, text2, subs2 = common.decode_match(t2)
   if name1 == name2 and text1 == text2
   then
      if subs1 then
	 -- subs exist
	 local mismatch = false;
	 for i = 1, #subs1 do
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

-- Before assigning a new (transformed) ast, push the current one onto the history list.
-- local function push_ast(pat, ast)
--    table.insert(pat.ast_history, 1, ast)
-- end

common.pattern = 
   recordtype.new("pattern",
		  { name=recordtype.NIL; -- for reference, debugging
		    peg=recordtype.NIL;	 -- lpeg pattern
		    uncap=false;	 -- peg without the top-level capture
		    tlpeg=false;	 -- top-level peg: tlpeg == peg * lpeg.Cp() 
		    alias=false;	 -- is this an alias or not
		    raw=false;		 -- true if the exp was raw at top level
		    ast=false;		 -- ast that generated this pattern, for pattern debugging
		    original_ast=false;	 -- ast after parser, before syntax expansion
		    extra=false;	 -- extra info that depends on node type
--                  source=unspecified;  -- source (rpl filename and line)
  }
)

common.boundary_identifier = "~"
common.any_char_identifier = "."
common.end_of_input_identifier = "$"

return common
