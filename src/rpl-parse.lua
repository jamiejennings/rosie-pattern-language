---- -*- Mode: Lua; -*- 
----
---- rpl-parse.lua    driver functions for RPL parser written in RPL
----
---- (c) 2016, Jamie A. Jennings
----

-- For user-written RPL:

parse = require "parse"
common = require "common"
compile = require "compile"

function rosie_parse_without_error_check(str, pos, tokens)
   pos = pos or 1
   tokens = tokens or {}
   local nt, nextpos, state = ROSIE_ENGINE:run(str, pos)
   if (not nt) then return tokens; end
   local name, pos, text, subs, subidx = common.decode_match(nt)
   table.move(subs, subidx, #subs, #tokens+1, tokens)	    -- strip the 'rpl' off the top
   return rosie_parse_without_error_check(str, nextpos, tokens)
end

function rosie_parse(str, pos, tokens)
   local astlist = rosie_parse_without_error_check(str, pos, tokens)
   local errlist = {};
   for _,a in ipairs(astlist) do
      if parse.syntax_error_check(a) then table.insert(errlist, a); end
   end
   return astlist, errlist
end

function parse_and_explain(source)
   assert(type(source)=="string", "Compiler: source argument is not a string: "..tostring(source))
   local astlist, errlist = rosie_parse(source)
   if #errlist~=0 then
--      io.write("Syntax errors:\n\n")
      io.write("(Note: Syntax error reporting is currently rather coarse.)\n")
      for _,e in ipairs(errlist) do
	 compile.explain_syntax_error(e, source)
	 io.write("\n")
	 return nil
      end
   else -- successful parse
      return astlist
   end
end
