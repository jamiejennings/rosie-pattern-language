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
local list = require "list"

local ESC = "\\"				    -- a single backslash


function ustring.codepoint_len(cp)
   if cp < 0x7F then return 1
   elseif cp < 0x7FF then return 2
   elseif cp < 0xFFFF then return 3
   else return 4
   end
end

-- Reduce a string, one pseudo-character at a time, where a pseudo-character is
-- either (1) a valid UTF-8 encoding of a Unicode codepoint (assigned or not),
-- OR (2) a single byte.
function ustring.reduce(f, accum, str, i)
   local cp_len = ustring.codepoint_len
   i = i or 1
   while i <= #str do
      local stopping_point = math.min(#str, i + 3)
      local ok, codepoint = pcall(utf8.codepoint, str, i, stopping_point)
      if ok then
	 local cp = codepoint
	 return ustring.reduce(f, f(accum, utf8.char(cp)), str, i+cp_len(cp))
      else
	 return ustring.reduce(f, f(accum, str:sub(i, i)), str, i+1)
      end
   end -- while
   return accum
end

-- Return the number of pseudo-characters in s 
function ustring.len(s)
   return ustring.reduce(function(len, _) return len+1; end,
			 0,
			 s)
end

-- Return a list of the pseudo-characters in s
function ustring.explode(s)
   local ls = {}
   ustring.reduce(function(_, next_char) table.insert(ls, next_char) end,
		  nil,
		  s)
   return ls
end
      

-- -----------------------------------------------------------------------------
-- Escape, un-escape
-- -----------------------------------------------------------------------------

local function simple_escape(char)
   return function(s, pos)
	     return char, pos+1
	  end
end

local function unicode_escape(s, start)
   local hex_chars = s:sub(start+1, start+4)
   local i, j = hex_chars:find('%x+')
   if (#hex_chars ~= 4) or (i ~= 1) or (j ~= 4) then
      return nil, "invalid unicode escape sequence: " .. ESC .. s:sub(start, start+4)
   end
   local codepoint = tonumber(hex_chars, 16)
--   assert((codepoint >= 0) and (codepoint <= 0xFFFF))
   return utf8.char(codepoint), start+5
end

local function Unicode_escape(s, start)
   local hex_chars = s:sub(start+1, start+8)
   local i, j = hex_chars:find('%x+')
   if (#hex_chars ~= 8) or (i ~= 1) or (j ~= 8) then
      return nil, "invalid Unicode escape sequence: " .. ESC .. s:sub(start, start+8)
   end
   local codepoint = tonumber(hex_chars, 16)
--   assert(codepoint >= 0)
   if codepoint > 0x10FFFF then
      return nil,
	 "invalid Unicode escape sequence (out of range): " .. ESC .. s:sub(start, start+8)
   end
   return utf8.char(codepoint), start+9
end

local function hex_escape(s, start)
   local hex_chars = s:sub(start+1, start+2)
   local i, j = hex_chars:find('%x+')
   if (#hex_chars ~= 2) or (i ~= 1) or (j ~= 2) then
      return nil, "invalid hex escape sequence: " .. ESC .. s:sub(start, start+2)
   end
   local byte_val = tonumber(hex_chars, 16)
   return string.char(byte_val), start+3
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
	    assert(type(nextpos)=="string")
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

function ustring.unescape_string(s)
   return ustring.unescape(s, ustring.mandatory_string_escapes)
end

-- Remove the double quotes surrounding an interpolated string, and
-- un-interpolate the contents
function ustring.dequote(str)
   if str:sub(1,1)=='"' then
      assert(str:sub(-1)=='"', 
	     "malformed quoted string: " .. str)
      return ustring.unescape_string(str:sub(2,-2))
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
		  if cp == 0x5C then
		     result = result .. ESC .. ESC
		  elseif cp == 0x7F then
		     result = result .. ESC .. 'x7F'
		  else
		     result = result .. string.char(cp)
		  end
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

ustring.inv_mandatory_charset_escapes = 
   { ['['] = '[';				 -- open bracket
     [']'] = ']';				 -- close bracket
     ['-'] = '-';				 -- hyphen / dash
     ['^'] = '^';				 -- caret (signifies complement)
  }

function ustring.escape_charlist(str)
   return ustring.escape(str, ustring.inv_mandatory_charset_escapes)
end

ustring.inv_mandatory_string_escapes =
   { ['"'] = '"' }

function ustring.escape_string(str)
   return ustring.escape(str, ustring.inv_mandatory_string_escapes)
end

function ustring.requote(str)
   return '"' .. ustring.escape_string(str) .. '"'
end

-- -----------------------------------------------------------------------------
-- Case transformation (for now, this is ASCII only)
-- -----------------------------------------------------------------------------

-- Arg is a lua string.  Only the first char in the string is examined, and it
-- is expected to be either a valid UTF-8 encoding of a Unicode character, or a
-- single byte (which by definition will be in the range 0x80-0xFF).

function ustring.upper(char)
   local ok, cp = pcall(utf8.codepoint, char)
   if ok and (cp >= 97) and (cp <= 122) then
      return string.char(cp - 32)
   end
   return nil
end
   
function ustring.lower(char)
   local ok, cp = pcall(utf8.codepoint, char)
   if ok and (cp >= 65) and (cp <= 90) then
      return string.char(cp + 32)
   end
   return nil
end
      
local function intersect_intervals(interval1, interval2)
   local s1, e1 = interval1[1], interval1[2]
   local s2, e2 = interval2[1], interval2[2]
   local low = math.max(s1, s2)
   local high = math.min(e1, e2)
   if low <= high then
      return { low, high }
   end
   return nil
end

-- Calculate the subranges between low/high (inclusive) of codepoints that are
-- cased letters, and return the other-case versions of those ranges.  ASCII only.
function ustring.cased_subranges(first, last)
   local low_codepoint = utf8.codepoint(first)
   local high_codepoint = utf8.codepoint(last)
   assert(low_codepoint <= high_codepoint)
   local ASCII_uppercase = {65, 90}
   local ASCII_lowercase = {97, 122}
   local range1_cp = intersect_intervals({low_codepoint, high_codepoint}, ASCII_uppercase)
   local range2_cp = intersect_intervals({low_codepoint, high_codepoint}, ASCII_lowercase)
   local cased_subranges_cp = list.filter(function(a) return a; end, list.from{range1_cp, range2_cp})
   local cased_subranges = list.map(function(r) return list.map(utf8.char, r) end, cased_subranges_cp)
   local other_cased_subranges =
      list.map(function(r) return { ustring.upper(utf8.char(r[1])) or ustring.lower(utf8.char(r[1])),
				    ustring.upper(utf8.char(r[2])) or ustring.lower(utf8.char(r[2])) }
	       end,
	       cased_subranges_cp)
   return cased_subranges, other_cased_subranges
end


return ustring


