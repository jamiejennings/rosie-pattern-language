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

assert(ROSIE_RPLX)				    -- compiled version of 'rpl'

local function rosie_parse_without_error_check(str, pos, tokens)
   pos = pos or 1
   local results = {}
   local tokens, leftover = ROSIE_RPLX:match(str, pos)
   assert(leftover==0)				    -- parser pattern ends with $
   local name, pos, text, subs = common.decode_match(tokens)
   -- strip off the "*" at the top by looking only at subs
   -- and strip the top 'rpl' off of each sub
   -- for _,token in ipairs(subs) do		    -- this loop is map_append
   --    local name, pos, text, subs = common.decode_match(token)
   --    table.move(subs, 1, #subs, #results+1, results)
   -- end
   -- return results
   return subs or {}
   
   -- pos = pos or 1
   -- tokens = tokens or {}
   -- local nt, leftover = ROSIE_RPLX:match(str, pos)
   -- if (not nt) then return tokens; end
   -- local name, pos, text, subs = common.decode_match(nt)
   -- table.move(subs, 1, #subs, #tokens+1, tokens)    -- strip the 'rpl' off the top
   -- return rosie_parse_without_error_check(str, #str-leftover+1, tokens)
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
