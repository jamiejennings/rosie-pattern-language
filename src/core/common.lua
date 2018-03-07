---- -*- Mode: Lua; -*-                                                                           
----
---- common.lua        Functions common to many parts of Rosie
----
---- © Copyright IBM Corporation 2016, 2017.
---- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
---- AUTHOR: Jamie A. Jennings

local lpeg = import "lpeg"
local R, P, S = lpeg.R, lpeg.P, lpeg.S
local util = import "util"
local recordtype = import "recordtype"
local NIL = recordtype.NIL
local math = import "math"
local string = import "string"
local table = import "table"
local os = import "os"

local common = {}				    -- interface

-- Return the first component of a dotted identifier (typically an rpl package id), and the rest. 
function common.split_id(name)
   local pkgname, localname
   local start, finish = name:find(".", 1, true)
   if start then
      return name:sub(1, finish-1), name:sub(finish+1)
   else
      return nil, name
   end
end

-- If first component (the package id) is nil or ".", then do not include it.
function common.compose_id(names)
   return table.concat(names, ".",
		       ((names[1] == nil) or (names[1] == ".")) and 2 or 1)
end

----------------------------------------------------------------------------------------
-- Path handling
----------------------------------------------------------------------------------------

-- parse_pathlist returns a table of the paths in pathlist, which is a colon separated list on
-- all platforms except windows, where it is a semi-colon separated list
function common.parse_pathlist(pathlist)
   assert(common.pathsep and (type(common.pathsep)=="string"))
   assert(type(pathlist)=="string")
   return util.split(pathlist, common.pathsep)
end

-- path assembles a path from its component directory names
function common.path(...)
   return table.concat({...}, common.dirsep)
end

-- We support a basic form of tilde expansion when the user enters a file name.  (Only ~/... is
-- supported, not the ~user/... syntax.)
function common.tilde_expand(dir)
   if dir:sub(1,2)=="~/" then
      local ok, HOMEDIR = pcall(os.getenv, "HOME")
      if (not ok) or (type(HOMEDIR)~="string") then
	 HOMEDIR = ""
      end
      return HOMEDIR .. dir:sub(2)
   end
   return dir
end

function common.get_file(filepath, searchpath, extension)
   extension = extension or ".rpl"
   local dirs = common.parse_pathlist(searchpath)
   if #dirs==0 then return nil, nil, "Error: search path is empty"; end
   local errs = {}
   for _, dir in ipairs(dirs) do
      local fullpath = common.tilde_expand(dir) .. common.dirsep .. filepath .. extension
      local contents, msg = util.readfile(fullpath)
      if contents then
	 return fullpath, contents, nil
      elseif contents==nil then
	 return fullpath, nil, "file not readable"
      else
	 table.insert(errs, msg)
      end
   end
   return nil, nil, table.concat(errs, "\n")
end


----------------------------------------------------------------------------------------
-- UTF-8 considerations
----------------------------------------------------------------------------------------
local b1_lead = lpeg.R(string.char(0x00)..string.char(0x7F))   -- ASCII (1 byte)
local b2_lead = lpeg.R(string.char(0xC0)..string.char(0xDF))
local b3_lead = lpeg.R(string.char(0xE0)..string.char(0xEF))
local b4_lead = lpeg.R(string.char(0xF0)..string.char(0xF7))
local c_byte = lpeg.R(string.char(0x80)..string.char(0xBF)) -- continuation byte

-- This is denoted \X in Perl, PCRE and some other regex
common.utf8_char_peg = b1_lead +
               (b2_lead * c_byte) +
	       (b3_lead * c_byte * c_byte) +
	       (b4_lead * c_byte * c_byte * c_byte) +
	       lpeg.P(1)			    -- fallback to any single byte

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
-- Assume Unix:
common.pathsep = ":"
-- Unless Windows:
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


----------------------------------------------------------------------------------------
-- Functions for logging informational messages (note) and warnings (warn) to stderr
----------------------------------------------------------------------------------------

common.notes = false;

function common.note(...)
   if (not common.notes) then return; end
   for _, item in ipairs{...} do io.stderr:write(item); end
   io.stderr:write("\n")
end

function common.warn(str, ...)
   local items = {...}
   table.insert(items, 1, "Warning: ")
   table.insert(items, 2, str)
   table.insert(items, "\n")
   for _, item in ipairs(items) do io.stderr:write(item); end
   io.stderr:flush()
end


----------------------------------------------------------------------------------------
-- AST functions
----------------------------------------------------------------------------------------

-- Note: walk_parse_tree is a function to traverse a parse tree.  One can call it with auxiliary
-- functions in order to do things like:
-- (1) Reveal the contents of the tree, i.e. generate the program the way the parser saw it
-- (2) Compile the program
-- (3) Eval interactively, so we can see where there are failures in pattern matching
--     The idea is that the match function is called with an expression.  If the match fails, then
--     the user invokes match again with debug turned on, and can then see how the matcher
--     actually worked.  In this mode, each pattern is compiled just in time.

function common.walk_parse_tree(a, functions, ...)
   assert(type(a)=="table", "walk_parse_tree: first argument not an ast: "..tostring(a))
   assert(type(a[1])~="table", "walk_parse_tree first argument not an ast (maybe it's a list of ast's?): "..tostring(a))
   assert(type(functions)=="table")
   local name, pos, text, subs = common.decode_match(a)
   local f = functions[name]
   if not f then f = functions.default; end
   if not f then
      if functions[1] then			    -- name of caller for debugging
	 error("walk_parse_tree called by "..functions[1]
	       ..": missing function to handle ast node type: " .. tostring(name))
      else
	 error("walk_parse_tree: missing function to handle ast node type: " .. tostring(name))
      end
   end
   return f(a, ...)
end

common.source = recordtype.new("source",
			       {s = NIL;        -- start position (1-based), defaults to 1
				e = NIL;	-- end+1 position (1-based), defaults to #text
				text = NIL;	-- the source itself
				origin = NIL;   -- describes where the source code came from
				                -- (nil for user input, else a loadrequest)
				parent = NIL;})

-- A loadrequest explains WHY we are compiling something, as follows:
-- 
-- (0) If there is no loadrequest object, then the source came from user input.
-- (1) When importpath is present, then we are compiling in order to 'import <importpath>'.
--     If prefix is present, we are trying to 'import <importpath> as <prefix>'.
--     If filename is present, the code we are compiling was found in '<filename>'.
--     If packagename is present, the code we are compiling declared 'package <packagename>'.
-- (2) When importpath is nil, the code we are compiling comes from '<filename>'.
common.loadrequest = recordtype.new("loadrequest",
				    {importpath = NIL;  -- X, when the requestor said "import X as Y"
				     prefix = NIL;      -- Y
				     packagename = NIL; -- filled in from the module source at load time
				     filename = NIL;})  -- filled in at load time

----------------------------------------------------------------------------------------
-- Matches
----------------------------------------------------------------------------------------
-- Matches are the data structure of the ASTs produced by the parser,
-- as well as the data structures produced by matching rpl expressions.

function common.create_match(name, pos, capture, ...)
   local subs = {...};
   if (not subs[1]) then subs=nil; end
   return {type = name, s = pos, data = capture, subs = subs};
end

-- Wrap a peg such that the resulting peg creates a match (AST) node that has this form:
-- {name = {text=<string>, pos=<int>}}
-- E.g.
--    [*: 
--     [text: "Hello", 
--      pos: 1]]

assert(lpeg.rcap, "lpeg.rcap not defined: wrong version of lpeg???")
assert(lpeg.rconstcap, "lpeg.rconstcap not defined: wrong version of lpeg???")
function common.match_node_wrap(peg, label)
   assert(lpeg.type(peg)=="pattern")
   assert(type(label)=="string")
   return lpeg.rcap(peg, label)
end

local function insert_input_text(m, input)
   if not m then return m; end			    -- abend can produce empty match
   local name, s, data, subs, e = common.decode_match(m)
   if data then return m; end			    -- const capture will have data already
   assert(type(e)=="number", "expected an end position, got: " .. tostring(data))
   m.data = input:sub(s, e-1)
   if subs then
      for i = 1, #subs do insert_input_text(subs[i], input); end
   end
   assert(type(m.data)=="string")
   return m
end

function common.match(peg, input, start, rmatch_encoder, fn_encoder, parms, total_time, lpegvm_time)
   local m, leftover, abend, t1, t2 = peg:rmatch(input, start, rmatch_encoder, total_time, lpegvm_time)
   if not m then return false, start, abend, t1, t2; end
   return fn_encoder(m, input, start, parms), leftover, abend, t1, t2
end

-- return the match name, source position, match text, and (if there are subs), the table with the
-- subs and the index of first sub.  (because there used to be other things in the sub table)

function common.decode_match(t)
   return t.type, t.s, t.data, t.subs, t.e
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
		     return tostring(v.major).."."..tostring(v.minor)
		  end)

common.compiler = 
   recordtype.new("compiler",
		  { version=false;	 -- rpl version supported
		    load=undefined;
		    import=undefined;
		    compile_expression=undefined;
		    parser=false;
		  })

-- parser operation:
--   parse source to produce parse tree;
--   transform parse tree as needed (e.g. syntax expand), producing ast;
--   return ast, table of errors, leftover count
--   if any step fails, generate useful errors and return nil, errors, leftover

common.parser =
   recordtype.new("parser",
		  { version=false;	 -- rpl version supported
		    preparse=undefined;
		    parse_statements=undefined;
		    parse_expression=undefined;
		    parse_deps=undefined;
		    prefixes=undefined;
		 })


local pkgtabletype =
   recordtype.new("pkgtable", {packagename=NIL,
			       env=NIL} )

function common.pkgtableref(tbl, importpath, prefix)
   local probe = tbl[importpath] and tbl[importpath][prefix or 1]
   if not probe then return nil; end
   return probe.packagename, probe.env
end

function common.pkgtableset(tbl, importpath, prefix, p, e)
   assert(p and e and type(importpath)=="string")
   local new_entry = pkgtabletype.new{packagename=p, env=e}
   if not tbl[importpath] then tbl[importpath] = {}; end
   tbl[importpath][prefix or 1] = new_entry
end

----------------------------------------------------------------------------------------
-- Binding types: novalue, pattern, macro, pfunction, value, environment
----------------------------------------------------------------------------------------

-- environment is defined in environment.lua

common.novalue =
   recordtype.new("novalue",
		  {exported=true;
		   ast=NIL;
		})

common.taggedvalue =
   recordtype.new("taggedvalue",		    -- tagged values that are not patterns
		  { type=NIL;
		    value=NIL;
		    exported=true;
		    ast=NIL;
		 })

common.pfunction =
   recordtype.new("pfunction",
		  { primop=NIL;			    -- if primitive, holds a lua function
		    exported=true;
		    ast=NIL;			    -- for origin
		  })

common.macro =
   recordtype.new("macro",
		  { primop=NIL;			    -- if primitive, holds a lua function
		    exported=true;
		    ast=NIL;			    -- for origin
		  })

common.pattern = 
   recordtype.new("pattern",
		  { name=NIL;            -- for reference, debugging
		    peg=NIL;		 -- lpeg pattern
		    exported=true;	 -- true when the binding to this pattern is exported
		    uncap=false;	 -- peg without the top-level capture
		    alias=false;	 -- is this an alias or not
		    ast=false;		 -- ast that generated this pattern, for pattern debugging
		    extra=false;	 -- extra info that depends on node type
--                  source=unspecified;  -- source (rpl filename and line)
  }
)

common.boundary_identifier = "~"
common.any_char_identifier = "."
common.end_of_input_identifier = "$"
common.start_of_input_identifier = "^"
common.halt_pattern_identifier = "halt"

-- This function is connected to the definition in rpl_1_1 of the tokens that constitute
-- "atmosphere", which is ambient blank lines and comments that should be ignored when creating an
-- ast. 
function common.not_atmosphere(sub)
   return (sub.type ~= "comment") and (sub.type ~= "newline")
end

function common.type_is_syntax_error(t)
   local names = util.split(t, ".")
   assert(type(names)=="table")
   return (names[#names]=="syntax_error")
end

----------------------------------------------------------------------------------------
-- Configuration items and attributes
----------------------------------------------------------------------------------------
common.attribute =
   recordtype.new("attribute",
		  {name=false;
		   value=false;
		   set_by=false;
		   description=false;
		})

function common.new_attribute(name, value, set_by, description)
   return common.attribute.factory{ name=tostring(name),
				    value=(value and tostring(value)) or "",
				    set_by=(set_by and tostring(set_by)) or "",
				    description=(description and tostring(description)) or ""}
end

function common.set_attribute(attribute_table, key, value, set_by)
   assert(type(value)=="string")
   assert(type(set_by)=="string")
   for _,entry in ipairs(attribute_table) do
      if entry.name == key then
	 entry.value = value
	 entry.set_by = set_by
	 return 
      end
   end -- for
   error("Internal error: attribute not found: " .. tostring(key))
end

function common.create_attribute_table(...)
   local at = {}
   local function search_by_name(self, name)
      if type(name) ~= "string" then return nil; end
      for _, entry in ipairs(self) do
	 if rawget(entry, "name") == name then return rawget(entry, "value"); end
      end
      return nil				    -- not found
   end
   for _, entry in ipairs{...} do
      assert(common.attribute.is(entry))
      table.insert(at, entry)
   end
   setmetatable(at, {__index = search_by_name})
   return at
end

-- return a table with attribute names as keys, and values as indices, for fast
-- lookup.
function common.attribute_table_to_table(at)
   local tbl = {}
   for _, entry in ipairs(at) do
      tbl[entry.name] = entry.value
   end
   return tbl
end

----------------------------------------------------------------------------------------
-- Output encoding functions
----------------------------------------------------------------------------------------

function common.byte_to_lua(m, input)
   return insert_input_text(lpeg.decode(m), input)
end

local identity_fn = function(...) return ... end

-- These constants are interpreted in the rpeg C code:
common.BYTE_ENCODING = 3
common.LINE_ENCODING = 2
common.JSON_ENCODING = 1

common.encoder_table = 
   setmetatable({ line = {common.LINE_ENCODING, identity_fn},
		  json = {common.JSON_ENCODING, identity_fn},
		  byte = {common.BYTE_ENCODING, identity_fn},
		  none = {common.BYTE_ENCODING, function(...) return nil end},
		  default = {common.BYTE_ENCODING, common.byte_to_lua},
	       },
		{__index = function(...) return {} end})

function common.encoder_returns_userdata(encoder)
   local fn = common.encoder_table[encoder]
   return fn and (fn[2] == identity_fn) and true
end

function common.add_encoder(name, rmatch_arg, fn)
   assert(rmatch_arg and fn, "bad arg to add_encoder")
   common.encoder_table[name] = {rmatch_arg, fn}
end

function common.lookup_encoder(name)
   local entry = common.encoder_table[name]
   return entry[1], entry[2]
end

-- Do not want to depend at all on the process or thread's locale setting.  This
-- is the C/Posix locale for the ascii character set.
common.locale = {
   alnum = R("09") + R("AZ") + R("az"),
   alpha = R("AZ") + R("az"),
   ascii = R(string.char(0x0, 0x7f)),
   blank = S(" \t"),
   cntrl = R(string.char(0x00, 0x1f)) + P(string.char(0x7f)),
   digit = R("09"),
   graph = R(string.char(0x21, 0x7e)),
   lower = R("az"),
   print = R(" ~"),
   punct = R("!/") + R(":@") + R("[`") + R("{~"),
   space = R("\t\r") + P(" "),
   upper = R("AZ"),
   word = R("09") + R("AZ") + R("az") + S("_"),
   xdigit = R("09") + R("AF") + R("af"),
}


return common
