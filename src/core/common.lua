---- -*- Mode: Lua; -*-                                                                           
----
---- common.lua        Functions common to many parts of Rosie
----
---- © Copyright IBM Corporation 2016, 2017.
---- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
---- AUTHOR: Jamie A. Jennings

local lpeg = import "lpeg"
local util = import "util"
local recordtype = import "recordtype"
local math = import "math"
local string = import "string"
local table = import "table"

local common = {}				    -- interface

----------------------------------------------------------------------------------------
-- Path handling
----------------------------------------------------------------------------------------

-- parse_path returns a table of the directories in path, which is a colon separated list
-- on all platforms except windows, where it is a semi-colon separated list
function common.parse_path(path)
   assert(common.pathsep)
   assert(type(path)=="string")
   local dirs = {}
   for dir in path:gmatch("([^" .. common.pathsep .. "]+)") do
      table.insert(dirs, dir)
   end
   return dirs
end

-- path assembles a path from its components
function common.path(...)
   return table.concat({...}, common.dirsep)
end

function common.get_file(filepath, searchpath, extension)
   extension = extension or ".rpl"
   local dirs = common.parse_path(searchpath)
   for _, dir in ipairs(dirs) do
      local fullpath = dir .. common.dirsep .. filepath .. '.' .. extension
      local contents = util.readfile(fullpath)
      if contents then return fullpath, contents; end
   end
   return nil
end


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
common.pathsep = ":"
if common.dirsep=="\\" then common.pathsep = ";" end

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
   { a = "\a";					    -- bell
     b = "\b";					    -- backspace
     f = "\f";					    -- formfeed
     n = "\n";					    -- newline
     r = "\r";					    -- return
     t = "\t";					    -- tab
     v = "\v"; 					    -- vertical tab
     ['\\'] = '\\';				    -- backslash
     ['"'] = '"';				    -- double quote
     ["'"] = "'";				    -- single quote
  }

function common.unescape_string(s, escape_table)
   -- the only escape character is \
   -- a literal backslash is obtained using \\
   escape_table = escape_table or common.escape_substitutions
   local result = ""
   local i = 1
   while (i <= #s) do
      if s:sub(i,i)=="\\" then
	 local escaped_char = s:sub(i+1,i+1)
	 local actual = escape_table[escaped_char]
	 if actual then
	    result = result .. actual
	    i = i + 2
	 else
	    return nil, escaped_char
	 end
      else
	 result = result .. s:sub(i,i)
	 i = i + 1
      end
   end -- for each character in s
   return result
end	    

function common.escape_string(s)
   return (string.format("%q", s)):sub(2,-2)
end

-- dequote removes double quotes surrounding an interpolated string, and un-interpolates the
-- contents 
function common.dequote(str)
   if str:sub(1,1)=='"' then
      assert(str:sub(-1)=='"', 
	     "malformed quoted string: " .. str)
      return common.unescape_string(str:sub(2,-2))
   end
   return str
end

local additional_escape_substitutions = 
   { ['['] = '[';				    -- open bracket
     [']'] = ']';				    -- close bracket
     ['^'] = '^';				    -- caret (signifies complement)
  }
   
common.charlist_escape_substitutions = {}
for k,v in pairs(common.escape_substitutions) do
   common.charlist_escape_substitutions[k] = v
end
for k,v in pairs(additional_escape_substitutions) do
   common.charlist_escape_substitutions[k] = v
end

function common.unescape_charlist(s)
   -- the only escape character is \
   -- these characters MUST be escaped: \^ \[ \] \\
   -- and no others.
   return common.unescape_string(s, common.charlist_escape_substitutions)
end

----------------------------------------------------------------------------------------
-- Functions for logging informational messages (note) and warnings (warn) to stderr
----------------------------------------------------------------------------------------

function common.note(...)
   for _, item in ipairs{...} do io.stderr:write(item); end
   io.stderr:write("\n")
end

function common.warn(str, ...) note("Warning: ", str, ..., "\n"); end


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
   local subs = {...};
   if (not subs[1]) then subs=nil; end
   return {type = name, s = pos, text = capture, subs = subs};
end

--common.create_match = lpeg.r_create_match
common.create_match = create_match

assert(lpeg.rcap, "lpeg.rcap not defined: wrong version of lpeg???")
common.match_node_wrap = lpeg.rcap

-- This could be done in C
local function insert_input_text(m, input)
   local name, s, text, subs, e = common.decode_match(m)
   assert(type(e)=="number", "expected an end position, got: " .. tostring(text))
   m.text = input:sub(s, e-1)
   if subs then
      for i = 1, #subs do insert_input_text(subs[i], input); end
   end
   assert(type(m.text)=="string")
   return m
end

function common.rmatch(peg, input, start, encode, total_time, lpegvm_time)
   local Cencoder = encode or 0			    -- default is compact byte encoding
   if encode==-1 then Cencoder = 0; end		    -- -1 ==> no output
   local m, nextpos, t1, t2 = peg:rmatch(input, start, Cencoder, total_time, lpegvm_time)
   if not m then return nil, nil, t1, t2; end
   if not encode then return insert_input_text(lpeg.decode(m), input), nextpos, t1, t2
   elseif encode==-1 then return nil, nextpos, t1, t2
   else return m, nextpos, t1, t2; end
end

-- return the match name, source position, match text, and (if there are subs), the table with the
-- subs and the index of first sub.  (because there used to be other things in the sub table)

function common.decode_match(t)
   return t.type, t.s, t.text, t.subs, t.e
end

----------------------------------------------------------------------------------------
-- Compiler and parser
----------------------------------------------------------------------------------------

local function undefined() assert(false, "undefined function"); end

common.rpl_version =
   recordtype.new("rpl_version",
		  { major=0;
		    minor=0;
		 },
		  function(maj, min)
		     if type(maj)~="number" or type(min)~="number" or 
		        (not math.tointeger(maj)) or (not math.tointeger(min)) then
			error("major and minor arguments must be integers")
		     end
		     return common.rpl_version.factory{major=maj; minor=min};
		  end,
		  function(v)
		     return "<rpl version " .. tostring(v.major).."."..tostring(v.minor) .. ">"
		  end)

common.compiler = 
   recordtype.new("compiler",
		  { version=false;	 -- rpl version supported
		    load=undefined;
		    import=undefined;
		    compile_expression=undefined;
		    parser=false;
		  })

common.parser =
   recordtype.new("parser",
		  { version=false;	 -- rpl version supported
		    preparse=undefined;
		    parse_statements=undefined;
		    parse_expression=undefined;
		    parse_deps=undefined;
		    prefixes=undefined;
		 })


----------------------------------------------------------------------------------------
-- Binding types: undeclared, pattern, pfunction, environment
----------------------------------------------------------------------------------------

common.undeclared =
   recordtype.new("undeclared", {})

common.pfunction =
   recordtype.new("pfunction", {})

-- TODO: get rid of original_ast?

common.pattern = 
   recordtype.new("pattern",
		  { name=recordtype.NIL; -- for reference, debugging
		    peg=recordtype.NIL;	 -- lpeg pattern
		    exported=true;	 -- true when the binding to this pattern is exported
		    uncap=false;	 -- peg without the top-level capture
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
