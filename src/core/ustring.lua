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

local ESC = "\\"				    -- a single backslash

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
	    return nil, escaped_char		    -- return the bad char
	 end
	 local actual, nextpos = translate(s, i+1)
	 if not actual then
	    return nil, nextpos			    -- return the bad sequence
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


-- Orig stuff below

ustring.escape_substitutions =
   { a = ("\a");
     b = ("\b");
     f = ("\f");
     n = ("\n");
     r = ("\r");
     t = ("\t");
     ['"'] = '"';
     [ESC] = ESC;
  }
ustring.unescape_substitutions = {}
for k,v in pairs(ustring.escape_substitutions) do ustring.unescape_substitutions[v]=k; end

ustring.string_escape_substitutions =
   { ['"'] = simple_escape('"') }

function ustring.unescape_string_literal(s)
   return ustring.unescape(s, ustring.string_escape_substitutions)
end


function ustring.escape_string(s, unescape_table)
   unescape_table = unescape_table or ustring.unescape_substitutions
   local result = ""
   local i = 1
   while (i <= #s) do
      local escaped_char = unescape_table[s:sub(i,i)]
      if escaped_char then
	 result = result .. '\\' .. escaped_char
	 i = i + 1
      elseif (s:sub(i,i) < ' ') or (s:sub(i,i) > '~') then
	 result = result .. '\\u' .. string.format('%04x', s:byte(i,i))
	 i = i + 1
      else
	 result = result .. s:sub(i,i)
	 i = i + 1
      end
   end -- for each character in s
   return result
end

-- dequote removes double quotes surrounding an interpolated string, and un-interpolates the
-- contents 
function ustring.dequote(str)
   if str:sub(1,1)=='"' then
      assert(str:sub(-1)=='"', 
	     "malformed quoted string: " .. str)
      return ustring.unescape(str:sub(2,-2))
   end
   return str
end

function ustring.requote(str)
   return '"' .. ustring.unescape(str) .. '"'
end

ustring.charset_escape_substitutions = 
   { ['['] = simple_escape('[');		 -- open bracket
     [']'] = simple_escape(']');		 -- close bracket
     ['-'] = simple_escape('-');		 -- hyphen / dash
     ['^'] = simple_escape('^');		 -- caret (signifies complement)
  }
   
-- ustring.charlist_escape_substitutions = {}
-- for k,v in pairs(ustring.escape_substitutions) do
--    ustring.charlist_escape_substitutions[k] = v
-- end
-- for k,v in pairs(ustring.charset_escape_substitutions) do
--    ustring.charlist_escape_substitutions[k] = v
-- end

function ustring.unescape_charlist(s)
   -- The only escape character is \.
   -- The characters in additional_escape_substitutions MUST be escaped.
   -- The sequences in escape_substitutions are allowed.
   return ustring.unescape(s, ustring.charset_escape_substitutions)
end

function ustring.unescape_char(char, translations, requirements)
   assert(type(char)=="string")
--    if char:sub(1,1)==ESC then
--       local translation = translations[char]
--       if translation then return translation; end
-- TEMP:
   return ustring.unescape_charlist(char)

end


return ustring


