-- -*- Mode: Lua; -*-                                                                             
--
-- rpl-parser.lua
--
-- © Copyright IBM Corporation 2016.
-- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
-- AUTHOR: Jamie A. Jennings


----------------------------------------------------------------------------------------
-- Driver functions for RPL parser written in RPL
----------------------------------------------------------------------------------------

local function rosie_parse_without_error_check(str, pos, tokens)
   pos = pos or 1
   tokens = tokens or {}
--   print("Calling ROSIE_ENGINE:match on: " .. str)
   local nt, leftover, state = ROSIE_ENGINE:match_(ROSIE_ENGINE.pattern, str, pos)
   if (not nt) then return tokens; end
   local name, pos, text, subs = common.decode_match(nt)
   table.move(subs, 1, #subs, #tokens+1, tokens)    -- strip the 'rpl' off the top
   return rosie_parse_without_error_check(str, #str-leftover+1, tokens)
end


local function rosie_parse(str, pos, tokens)
   local astlist = rosie_parse_without_error_check(str, pos, tokens)
   local errlist = {};
   for _,a in ipairs(astlist) do
      if parse.syntax_error_check(a) then table.insert(errlist, a); end
   end
   return list.map(syntax.top_level_transform, astlist), errlist, astlist
end

function parse_and_explain(source)
   assert(type(source)=="string", "Compiler: source argument is not a string: "..tostring(source))
   local astlist, errlist, original_astlist = rosie_parse(source)
   if #errlist~=0 then
      local msg = "Warning: syntax error reporting is limited at this time\n"
      for _,e in ipairs(errlist) do
	 msg = msg .. parse.explain_syntax_error(e, source) .. "\n"
      end
      return false, msg
   else -- successful parse
      return astlist, original_astlist
   end
end
