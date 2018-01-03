-- -*- Mode: Lua; -*-                                                                             
--
-- ustring.lua   Operations on UTF-8 characters and strings
--
-- © Copyright Jamie A. Jennings 2018.
-- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
-- AUTHOR: Jamie A. Jennings

local ustring = {}

local ESC = "\\"				    -- a single backslash

ustring.escape_substitutions =			    -- characters that change when escaped are:
   { a = "\a";					    -- bell
     b = "\b";					    -- backspace
     f = "\f";					    -- formfeed
     n = "\n";					    -- newline
     r = "\r";					    -- return
     t = "\t";					    -- tab
     [ESC] = ESC;				    -- backslash
     ['"'] = '"';				    -- double quote
  }

ustring.unescape_substitutions = {}
for k,v in pairs(ustring.escape_substitutions) do ustring.unescape_substitutions[v]=k; end

function ustring.unescape_string(s, escape_table)
   -- the only escape character is \
   -- a literal backslash is obtained using \\
   escape_table = escape_table or ustring.escape_substitutions
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
      return ustring.unescape_string(str:sub(2,-2))
   end
   return str
end

function ustring.requote(str)
   return '"' .. ustring.unescape_string(str) .. '"'
end

ustring.charset_escape_substitutions = 
   { ['['] = '[';				    -- open bracket
     [']'] = ']';				    -- close bracket
     ['-'] = '-';				    -- hyphen / dash
     ['^'] = '^';				    -- caret (signifies complement)
  }
   
ustring.charlist_escape_substitutions = {}
for k,v in pairs(ustring.escape_substitutions) do
   ustring.charlist_escape_substitutions[k] = v
end
for k,v in pairs(ustring.charset_escape_substitutions) do
   ustring.charlist_escape_substitutions[k] = v
end

function ustring.unescape_charlist(s)
   -- The only escape character is \.
   -- The characters in additional_escape_substitutions MUST be escaped.
   -- The sequences in escape_substitutions are allowed.
   return ustring.unescape_string(s, ustring.charlist_escape_substitutions)
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


