-- -*- Mode: Lua; -*-                                                                             
--
-- rpl-parser.lua
--
-- © Copyright IBM Corporation 2016, 2017.
-- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
-- AUTHOR: Jamie A. Jennings


----------------------------------------------------------------------------------------
-- Driver functions for RPL parser written in RPL
----------------------------------------------------------------------------------------

local function rosie_parse_without_error_check(rplx, str, pos, tokens)
   pos = pos or 1
   local results = {}
   local tokens, leftover = rplx:match(str, pos)
   local name, pos, text, subs = common.decode_match(tokens)
   return subs or {}, leftover
end

local function rosie_parse(rplx, str, pos, tokens)
   local astlist, leftover = rosie_parse_without_error_check(rplx, str, pos, tokens)
   local errlist = {};
   for _,a in ipairs(astlist) do
      if parse.syntax_error_check(a) then table.insert(errlist, a); end
   end
   return astlist, errlist, leftover
end

local function preparse(rplx_preparse, source)
   local major, minor
   local language_decl, leftover = rplx_preparse:match(source)
   if language_decl then
      if parse.syntax_error_check(language_decl) then
	 return false, "Syntax error in language version declaration: " .. language_decl.text
      else
	 major = tonumber(language_decl.subs[1].subs[1].text) -- major
	 minor = tonumber(language_decl.subs[1].subs[2].text) -- minor
	 return major, minor, #source-leftover+1
      end
   else
      return nil, nil, 1
   end
end   

local function vstr(maj, min)
   return tostring(maj) .. "." .. tostring(min)
end

function make_parse_and_explain(rplx_preparse, rplx_rpl, rpl_maj, rpl_min, syntax_expand)
   return function(source)
	     assert(type(source)=="string", "Error: source argument is not a string: "..tostring(source))
	     -- preparse to look for rpl language version declaration
	     local major, minor, pos = preparse(rplx_preparse, source)
	     local rpl_warning
	     if major then
		if rpl_maj > major then
		   -- Warn in case major version not backwards compatible
		   rpl_warning = "Warning: loading rpl at version " .. 
		                 vstr(major, minor) .. 
			         " into engine at version " .. 
			         vstr(rpl_maj, rpl_min)
		elseif (rpl_maj < major) or ((rpl_maj == major) and (rpl_min < minor)) then
		   return nil,
		          nil,
		          {"Error: loading rpl that requires version " .. 
			   vstr(major, minor) .. " but engine is at version " .. 
			   vstr(rpl_maj, rpl_min)}
		end
	     end
	     -- TODO: add a check for "debugging output" here
	     if major then
	     	io.stderr:write("-> Parser noted rpl version declaration ", vstr(major, minor), "\n")
	     else
	     	io.stderr:write("-> Parser saw no rpl version declaration\n")
	     end
	     local original_astlist, errlist, leftover = rosie_parse(rplx_rpl, source, pos)
	     local astlist = syntax_expand(original_astlist)
	     if #errlist~=0 then
		local msgs = {}
		if rpl_warning then table.insert(msgs, rpl_warning); end
		table.insert(msgs, "Warning: syntax error reporting is limited at this time")
		for _,e in ipairs(errlist) do
		   table.insert(msgs, parse.explain_syntax_error(e, source))
		end
		return nil, nil, msgs, leftover
	     else -- successful parse
		local warnings = {}
		if rpl_warning then table.insert(warnings, rpl_warning); end
		return astlist, original_astlist, warnings, leftover
	     end
	  end
end
