-- -*- Mode: Lua; -*-                                                                             
--
-- ustring.lua   Operations on UTF-8 characters and strings
--
-- © Copyright Jamie A. Jennings 2018.
-- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
-- AUTHOR: Jamie A. Jennings

-- This code is not meant to be generally useful.  It was written specifically
-- for Rosie Pattern Language.

local ustring = {}
local utf8 = require "utf8"

local ESC = "\\"				    -- a single backslash

-- Return the number of pseudo-characters, where a pseudo-character is either a
-- valid UTF-8 encoding of a Unicode codepoint (assigned or not), OR a single
-- byte. 
function ustring.len(s)
   local total = 0
   local i = 1
   while true do
      local len, badpos = utf8.len(s, i)
      if len then
	 return len+total
      else
	 len = ((badpos - i) > 1) and utf8.len(s, i, badpos-1) or 0
	 total = total + len + 1
	 i = badpos + 1
      end
   end -- while
   return total
end
      
local function simple_escape(char)
   return function(s, pos)
	     return char, pos+1
	  end
end

local function unicode_escape(...)
end
local function Unicode_escape(...)
end
local function hex_escape(...)
end

ustring.translations =		     -- characters that change when escaped are:
   { a = simple_escape("\a");	     -- bell
     b = simple_escape("\b");	     -- backspace
     f = simple_escape("\f");	     -- formfeed
     n = simple_escape("\n");	     -- newline
     r = simple_escape("\r");	     -- return
     t = simple_escape("\t");	     -- tab
     [ESC] = simple_escape(ESC);     -- backslash
     u = unicode_escape;
     U = Unicode_escape;
     x = hex_escape;
  }

function ustring.unescape(s, mandatories)
   local translations = ustring.translations
   local result = ""
   local i = 1
   while (i <= #s) do
      if s:sub(i,i)==ESC then
	 local escaped_char = s:sub(i+1,i+1)
	 local translate = (mandatories and mandatories[escaped_char]) or translations[escaped_char]
	 if not translate then
	    return nil, "invalid escape sequence: " .. ESC .. escaped_char
	 end
	 local actual, nextpos = translate(s, i+1)
	 if not actual then
	    return nil, nextpos			    -- nextpos is error message
	 end
	 assert(type(actual)=="string")
	 assert(type(nextpos)=="number")
	 assert(nextpos > i)
	 result = result .. actual
	 i = nextpos
      elseif mandatories and mandatories[s:sub(i,i)] then
	 return nil, s:sub(i,i) .. " requires escaping in this context"
      else
	 result = result .. s:sub(i,i)
	 i = i + 1
      end
   end -- for each character in s
   return result
end	    

ustring.mandatory_string_escapes =
   { ['"'] = simple_escape('"') }

function ustring.unescape_string_literal(s)
   return ustring.unescape(s, ustring.mandatory_string_escapes)
end

-- Remove the double quotes surrounding an interpolated string, and
-- un-interpolate the contents
function ustring.dequote(str)
   if str:sub(1,1)=='"' then
      assert(str:sub(-1)=='"', 
	     "malformed quoted string: " .. str)
      return ustring.unescape_string_literal(str:sub(2,-2))
   end
   return str
end

ustring.charset_escape_substitutions = 
   { ['['] = simple_escape('[');		 -- open bracket
     [']'] = simple_escape(']');		 -- close bracket
     ['-'] = simple_escape('-');		 -- hyphen / dash
     ['^'] = simple_escape('^');		 -- caret (signifies complement)
  }
   
function ustring.unescape_charlist(s)
   -- The only escape character is \.
   -- The characters in additional_escape_substitutions MUST be escaped.
   -- The sequences in escape_substitutions are allowed.
   return ustring.unescape(s, ustring.charset_escape_substitutions)
end

-- -----------------------------------------------------------------------------
-- Escaping: Converting a UTF-8 string into an ASCII string that, when
-- unescaped, gives the same UTF-8 string again.
-- -----------------------------------------------------------------------------

ustring.inv_translations =
   { ["\a"] = "a";				    -- bell
     ["\b"] = "b";				    -- backspace
     ["\f"] = "f";				    -- formfeed
     ["\n"] = "n";				    -- newline
     ["\r"] = "r";				    -- return
     ["\t"] = "t";				    -- tab
     [ESC] = ESC;				    -- backslash
  }

function ustring.escape(s, inv_mandatories)
   local result = ""
   local i = 1
   while (i <= #s) do
      local current = s:sub(i,i)
      local c = inv_mandatories and inv_mandatories[current]
      if c then
	 result = result .. ESC .. c
	 i = i + 1
      else
	 c = ustring.inv_translations[current]
	 if c then
	    result = result .. ESC .. c
	    i = i + 1
	 else
	    local ok, cp = pcall(utf8.codepoint, s, i, i)
	    if ok and (cp >= 0x20) then
	       if cp <= 0x7F then
		  result = result .. string.char(cp)
		  i = i + 1
	       elseif cp <= 0xFFFF then
		  local hex = string.format("%04X", cp)
		  result = result .. ESC .. "u" .. hex
		  if cp < 0x7FF then
		     i = i + 2
		  else
		     i = i + 3
		  end
	       else
		  local hex = string.format("%08X", cp)
		  result = result .. ESC .. "U" .. hex
		  i = i + 4
	       end
	    else
	       -- Not valid utf8, or ASCII control character, so encode as a
	       -- byte and keep going
	       local hex = string.format("%02X", s:byte(i,i))
	       result = result .. ESC .. "x" .. hex
	       i = i + 1
	    end
	 end -- translation or not
      end -- mandatory or not
   end -- while
   return result
end	       

ustring.inv_mandatory_string_escapes =
   { ['"'] = '"' }

function ustring.requote(str)
   return '"' .. ustring.escape(str, ustring.inv_mandatory_string_escapes) .. '"'
end


return ustring


