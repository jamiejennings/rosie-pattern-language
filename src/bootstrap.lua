---- -*- Mode: Lua; -*- 
----
---- bootstrap.lua      Bootstrap Rosie by using the native Lua parser to parse rosie-core.rpl
----
---- (c) 2015, Jamie A. Jennings
----

local compile = require "compile"
require "engine"
require "os"

-- ROSIE_HOME should be set before entry to this code
if not ROSIE_HOME then error("ROSIE_HOME not set.  Exiting..."); os.exit(-1); end

ROSIE_VERSION = io.lines(ROSIE_HOME.."/VERSION")();

-- Create a matching engine for processing Rosie Pattern Language files

ROSIE_ENGINE = engine("RPL engine", {}, compile.new_env())

function bootstrap()
   compile.compile_core(ROSIE_HOME.."/src/rosie-core.rpl", ROSIE_ENGINE.env)
   ROSIE_ENGINE.program = { compile.core_compile_command_line_expression('rpl', ROSIE_ENGINE.env) }
end

-- For user-written RPL:

parse = require "parse"

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
