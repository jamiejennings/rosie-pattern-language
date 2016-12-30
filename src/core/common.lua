---- -*- Mode: Lua; -*-                                                                           
----
---- common.lua        Functions common to many parts of Rosie
----
---- © Copyright IBM Corporation 2016.
---- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
---- AUTHOR: Jamie A. Jennings

----------------------------------------------------------------------------------------
-- NOTE: The reason that this set of common functions exists is that Rosie's internal
-- AST now has the same structure as the Rosie output (a match).  So, AST functions
-- are now match functions, and vice versa.
----------------------------------------------------------------------------------------

--local co = require "color-output"

local lpeg = require "lpeg"
local Cc, Cg, Ct, Cp, C = lpeg.Cc, lpeg.Cg, lpeg.Ct, lpeg.Cp, lpeg.C

local os = require "os"
local util = require "util"
local recordtype = require "recordtype"
local unspecified = recordtype.unspecified

local common = {}				    -- interface

--assert(ROSIE_HOME, "The variable ROSIE_HOME is not set in common.lua")

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
local utf8_char_peg = b1_lead +
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
      elseif (#sym>2) and (sym:sub(1,1)=="(") and (sym:sub(-1,-1)==")") then
	 local env_value = os.getenv(sym:sub(2,-2))
	 if (not env_value) or (env_value=="") then
	    return false, string.format("Environment variable %q not set", sym:sub(2,-2))
	 end
	 full_path = env_value .. rest
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

function common.compact_messages(tbl)
   if type(tbl)~="table" then return tbl; end
   -- otherwise, always return a table of zero or more strings
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

function common.print_env(env, filter, skip_header, total)
   -- print a sorted list of patterns contained in the flattened table 'env'
   local pattern_list = {}

   local n = next(env)
   while n do
      table.insert(pattern_list, n)
      n = next(env, n);
   end
   table.sort(pattern_list)
   local patterns_loaded = #pattern_list
   total = (total or 0) + patterns_loaded
   local filter = filter and string.lower(filter) or nil
   local filter_total = 0

   local fmt = "%-30s %-15s %-8s"

   if not skip_header then
      print();
      print(string.format(fmt, "Pattern", "Type", "Color"))
      print("------------------------------ --------------- --------")
   end
   local kind, color;
   if filter == nil then
      for _,v in ipairs(pattern_list) do
         print(string.format(fmt, v, env[v].type, env[v].color))
      end
   else
      for _,v in ipairs(pattern_list) do
         local s,e = string.find(string.lower(tostring(v)), filter)
         if s ~= nil then
            print(string.format(fmt, v, env[v].type, env[v].color))
            filter_total = filter_total + 1
         end
      end
   end
   if patterns_loaded==0 then
      print("<empty>");
   end
   if not skip_header then
      print()
      if filter == nil then
         print(total .. " patterns")
      else
         print(filter_total .. " / " .. total .. " patterns")
      end
   end
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

function common.create_match(name, pos, capture, ...)
   local t = {};
   t.pos = pos;
   t.text=capture;
   t.subs = {...};
   if (not t.subs[1]) then t.subs=nil; end
   return {[name]=t};
end

function common.match_node_wrap(peg, name)
   return (Cc(name) * Cp() * peg) / common.create_match
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
   recordtype.define(
   {  name=unspecified;			 -- for reference, debugging
      peg=unspecified;			 -- lpeg pattern
      uncap=false;			 -- peg without the top-level capture
      alias=false;			 -- is this an alias or not
      raw=false;                         -- true if the exp was raw at top level
      ast=false;			 -- ast that generated this pattern, for pattern debugging
      original_ast=false;
      
--      source=unspecified;		 -- source (rpl filename and line)
--      uuid=unspecified;

  },
   "pattern"
)

---------------------------------------------------------------------------------------------------
-- Environment functions and initial environment
---------------------------------------------------------------------------------------------------

local b_id, dot_id, eol_id = "~", ".", "$"

common.boundary_identifier = b_id
common.any_char_identifier = dot_id
common.end_of_input_identifier = eol_id

----------------------------------------------------------------------------------------
-- Boundary for tokenization... this is going to be customizable, but hard-coded for now
----------------------------------------------------------------------------------------

local locale = lpeg.locale()
local boundary = locale.space^1 + #locale.punct
              + (lpeg.B(locale.punct) * #(-locale.punct))
	      + (lpeg.B(locale.space) * #(-locale.space))
	      + lpeg.P(-1)
	      + (- lpeg.B(1))

common.boundary = boundary

-- Base environment, which can be extended with new_env, but not written to directly,
-- because it is shared between match engines:

local pattern = common.pattern
	   
local ENV = {[dot_id] = pattern{name=dot_id; peg=utf8_char_peg; alias=true; raw=true};  -- any single character
             [eol_id] = pattern{name=eol_id; peg=lpeg.P(-1); alias=true; raw=true}; -- end of input
             [b_id] = pattern{name=b_id; peg=boundary; alias=true; raw=true}; -- token boundary
       }
setmetatable(ENV, {__tostring = function(env)
				   return "<base environment>"
				end;
		   __newindex = function(env, key, value)
				   error('Compiler: base environment is read-only, '
					 .. 'cannot assign "' .. key .. '"')
				end;
		})

function common.new_env(base_env)
   local env = {}
   base_env = base_env or ENV
   setmetatable(env, {__index = base_env;
		      __tostring = function(env) return "<environment>"; end;})
   return env
end

function common.flatten_env(env, output_table)
   output_table = output_table or {}
   local kind, color
   for item, value in pairs(env) do
      -- environments are nested, so we if already have a binding for 'item', we don't want to
      -- overwrite it with one from a parent environment:
      if not output_table[item] then
	 kind = (value.alias and "alias") or "definition"
	 if (co and co.colormap) then color = co.colormap[item] or ""; else color = ""; end;
	 output_table[item] = {type=kind, color=color}
      end
   end
   local mt = getmetatable(env)
   if mt and mt.__index then
      -- there is a parent environment
      return common.flatten_env(mt.__index, output_table)
   else
      return output_table
   end
end

-- use this print function to see the nested environments
function common.print_env_internal(env, skip_header, total)
   -- build a list of patterns that we can sort by name
   local pattern_list = {}
   local n = next(env)
   while n do
      table.insert(pattern_list, n)
      n = next(env, n);
   end
   table.sort(pattern_list)
   local patterns_loaded = #pattern_list
   total = (total or 0) + patterns_loaded

   local fmt = "%-30s %-15s %-8s"

   if not skip_header then
      print();
      print(string.format(fmt, "Pattern", "Kind", "Color"))
      print("------------------------------ --------------- --------")
   end

   local kind, color;
   for _,v in ipairs(pattern_list) do 
      local kind = (v.alias and "alias") or "definition";
      if (co and co.colormap) then color = co.colormap[v] or ""; else color = ""; end;
      print(string.format(fmt, v, kind, color))
   end

   if patterns_loaded==0 then
      print("<empty>");
   end
   local mt = getmetatable(env)
   if mt and mt.__index then
      print("\n----------- Parent environment: -----------\n")
      common.print_env_internal(mt.__index, true, total)
   else
      print()
      print(total .. " patterns loaded")
   end
end

return common
