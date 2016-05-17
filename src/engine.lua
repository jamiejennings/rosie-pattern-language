---- -*- Mode: Lua; -*-                                                                           
----
---- engine.lua    The RPL matching engine
----
---- © Copyright IBM Corporation 2016.
---- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
---- AUTHOR: Jamie A. Jennings


----------------------------------------------------------------------------------------
-- Engine
----------------------------------------------------------------------------------------
-- A matching engine is a Lua object that has state as follows:
--   env: environment of defined patterns
--   config: various configuration settings, including the default pattern to match
--   id: a string meant to be a unique identifier (currently unique in the Lua state)

local compile = require "compile"
local eval = require "eval"
local recordtype = require("recordtype")
local unspecified = recordtype.unspecified;

engine = 
   recordtype.define(
   {  name=unspecified;				    -- for reference, debugging
      env=false;
      config=false;
      id=unspecified;
      --
      match=false;
      match_file=false;
      eval=false;
      eval_file=false;
      configure=false;
      inspect=false;
--      match_using_exp=false;
  },
   "engine"
)

engine.tostring_function = function(orig, e)
			      return '<engine: '..tostring(e.name)..' ('.. e.id ..')>'; end

local locale = lpeg.locale()

local function identity_function(...) return ...; end

local function engine_error(e, msg)
   error(string.format("Engine %s (%s): %s", e.name, e.id, tostring(msg)), 0)
end

local function no_pattern(e)
   engine_error(e, "no pattern configured")
end

local function engine_configure(e, configuration)
   assert(type(configuration)=="table", "engine configuration not a table: " .. tostring(configuration))
   if configuration.expression then
      e.config.expression = configuration.expression
      local pat, msg = compile.compile_command_line_expression(configuration.expression, e.env)
      if not pat then engine_error(e, msg); end
      e.config.pattern = pat
   end
   if configuration.encoder then
      e.config.encoder = configuration.encoder
   end
   if configuration.pattern then		    -- need this for grep functionality, FOR NOW
      e.config.pattern = configuration.pattern
   end
   --
   -- Ensure some reasonable defaults when we can
   --
   e.config.encoder = e.config.encoder or identity_function
   --
   -- Check for common errors
   --
   if type(e.config.encoder)~="function" then
      engine_error(e, "encoder not a function: " .. tostring(e.config.encoder))
   end
end

local function engine_inspect(e)
   local representation = {}
   for k,v in pairs(e.config) do representation[k]=tostring(v); end
   return e.name, representation
end

local function engine_match(e, input, start)
   start = start or 1
   if not e.config.pattern then no_pattern(e); end
   local result, nextpos = compile.match_peg(e.config.pattern.peg, input, start)
   if result then return (e.config.encoder(result)), nextpos;
   else return false, 1; end
end

local function engine_eval(e, input, start)
   start = start or 1
   if not e.config.pattern then no_pattern(e); end
   local ok, matches, nextpos, trace = eval.eval(e.config.pattern, input, 1, e.env)
   if not ok then return false, matches; end
   if matches then
      assert(type(matches)=="table", "eval should return a table, not this: " .. tostring(matches))
      assert(not matches[2], "eval should return exactly 0 or 1 match")
      return (e.config.encoder(matches[1])), nextpos, trace
   else return false, 1, trace; end
end

local function open3(e, infilename, outfilename, errfilename)
   if type(infilename)~="string" then engine_error(e, "bad input file name"); end
   if type(outfilename)~="string" then engine_error(e, "bad output file name"); end
   if type(errfilename)~="string" then engine_error(e, "bad error file name"); end   
   local infile, outfile, errfile, msg
   if #infilename==0 then infile = io.stdin;
   else infile, msg = io.open(infilename, "r"); if not infile then error(msg, 0); end; end
   if #outfilename==0 then outfile = io.stdout
   else outfile, msg = io.open(outfilename, "w"); if not outfile then error(msg, 0); end; end
   if #errfilename==0 then errfile = io.stderr;
   else errfile, msg = io.open(errfilename, "w"); if not errfile then error(msg, 0); end; end
   return infile, outfile, errfile
end

local function engine_process_file(e, eval_flag, infilename, outfilename, errfilename)
   if not e.config.pattern then no_pattern(e); end
   local peg = (e.config.pattern.peg * Cp())
   if not (eval_flag==true or eval_flag==false) then engine_error(e, "bad eval flag"); end
   local infile, outfile, errfile = open3(e, infilename, outfilename, errfilename);

   local inlines, outlines, errlines = 0, 0, 0;
   local result, nextpos, m;
   local encode = (eval_flag and identity_function) or e.config.encoder;
   local nextline = infile:lines();
   local l = nextline(); 
   while l do
      if eval_flag then m, nextpos, result = engine_eval(e, l);
      else result, nextpos = peg:match(l); end
      -- What to do with nextpos and this useful calculation: (#input_text - nextpos + 1) ?
      -- Send it in a message to stderr?
      if result then
	 outfile:write(encode(result), "\n")
	 outlines = outlines + 1
      else
	 errfile:write(l, "\n")
	 errlines = errlines + 1
      end
      inlines = inlines + 1
      l = nextline(); 
   end -- while
   infile:close(); outfile:close(); errfile:close();
   return inlines, outlines, errlines
end

local function engine_match_file(e, infilename, outfilename, errfilename)
   return engine_process_file(e, false, infilename, outfilename, errfilename)
end

local function engine_eval_file(e, infilename, outfilename, errfilename)
   return engine_process_file(e, true, infilename, outfilename, errfilename)
end

engine.create_function =
   function(_new, name, initial_env)
      initial_env = initial_env or compile.new_env()
      -- assigning a unique instance id should be part of the recordtype module
      local id = tostring({}):match("0x(.*)") or "id/err"
      return _new{name=name,
		  env=initial_env,
		  id=id,
		  config={encoder=identity_function},	    -- defaults
		  match=engine_match,
		  match_file=engine_match_file,
		  eval=engine_eval,
		  eval_file=engine_eval_file,
		  configure=engine_configure,
		  inspect=engine_inspect}
   end

