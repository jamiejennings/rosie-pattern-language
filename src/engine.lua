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

local common = require "common"
local compile = require "compile"
local eval = require "eval"
local json = require "cjson"
local recordtype = require("recordtype")
local unspecified = recordtype.unspecified;
require "color-output"

engine = 
   recordtype.define(
   {  name=unspecified;				    -- for reference, debugging
      env=false;
      id=unspecified;
      --
      encoder=false;
      encoder_function=false;
      expression=false;
      pattern=false;
      --
      match=false;
      match_file=false;
      eval=false;
      eval_file=false;
      configure=false;
      inspect=false;
      --
      compile=false;
      compile_match_exp=false;
  },
   "engine"
)

engine.tostring_function = function(orig, e)
			      return '<engine: '..tostring(e.name)..' ('.. e.id ..')>'; end

local locale = lpeg.locale()

local function engine_error(e, msg)
   error(string.format("Engine %s (%s): %s", e.name, e.id, tostring(msg)), 0)
end

local function no_pattern(e)
   engine_error(e, "no pattern configured")
end

local function no_encoder(e)
   engine_error(e, "no encoder configured")
end

----------------------------------------------------------------------------------------

local encoder_table =
   {json = json.encode,
    color = color_string_from_leaf_nodes,
    nocolor = string_from_leaf_nodes,
    fulltext = common.match_to_text,
    [false] = function(...) return ...; end
 }

function name_to_encoder(name)
   return encoder_table[name]
end

function encoder_to_name(fcn)
   for k,v in pairs(encoder_table) do
      if v==fcn then return k; end
   end
   return "<unknown encoder>"
end

----------------------------------------------------------------------------------------

local function engine_configure(e, configuration)
   for k,v in pairs(configuration) do
      if k=="expression" then
	 local pat, msg = compile.compile_match_expression(v, e.env)
	 if not pat then return false, msg; end
	 e.expression = v
	 e.pattern = pat
      elseif k=="encoder" then
	 local f = name_to_encoder(v)
	 if type(f)~="function" then
	    return false, 'invalid encoder name: "' .. tostring(v) .. '"'
	 else
	    e.encoder = v
	    e.encoder_function = f
	 end
      elseif k=="name" then
	 e.name = tostring(v)
      else
	 return false, 'invalid configuration parameter: ' .. tostring(k)
      end
   end -- for each configuration key/value
   return true
end

local function engine_inspect(e)
   return {name=e.name, expression=e.expression, encoder=e.encoder, id=e.id}
end

local function engine_match(e, input, start)
   start = start or 1
   local result, nextpos = (e.pattern.peg * lpeg.Cp()):match(input, start)
   if result then return (e.encoder_function(result)), nextpos;
   else return false, 1; end
end

local function engine_eval(e, input, start)
--   return matches, nextpos, trace
   return eval.eval(e.pattern, input, start, e.env, false)
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

local function engine_process_file(e, eval_flag, infilename, outfilename, errfilename, wholefileflag)
   local peg = (e.pattern.peg * Cp())
   if type(eval_flag)~="boolean" then engine_error(e, "bad eval flag"); end
   if not e.encoder_function then engine_error(e, "output encoder required, but not set"); end
   local ok, infile, outfile, errfile = pcall(open3, e, infilename, outfilename, errfilename);
   if not ok then return false, infile; end	    -- infile is the error message in this case

   local inlines, outlines, errlines = 0, 0, 0;
   local trace, nextpos, m;
   local encode = e.encoder_function;
   local nextline
   if wholefileflag then
      nextline = function()
		    if wholefileflag then
		       wholefileflag = false;
		       return infile:read("a")
		    end
		 end
   else
      nextline = infile:lines();
   end
   local o_write, e_write = outfile.write, errfile.write
   local match = peg.match
   local l = nextline(); 
   while l do
      if eval_flag then _, _, trace = engine_eval(e, l); end
      m, nextpos = match(peg, l);
      -- What to do with nextpos and this useful calculation: (#input_text - nextpos + 1) ?
      if trace then o_write(outfile, trace, "\n"); end
      if m then
	 o_write(outfile, encode(m), "\n")
	 outlines = outlines + 1
      else --if not eval_flag then
	 e_write(errfile, l, "\n")
	 errlines = errlines + 1
      end
      if trace then o_write(outfile, "\n"); end
      inlines = inlines + 1
      l = nextline(); 
   end -- while
   infile:close(); outfile:close(); errfile:close();
   return inlines, outlines, errlines
end

local function engine_match_file(e, infilename, outfilename, errfilename, wholefileflag)
   return engine_process_file(e, false, infilename, outfilename, errfilename, wholefileflag)
end

local function engine_eval_file(e, infilename, outfilename, errfilename, wholefileflag)
   return engine_process_file(e, true, infilename, outfilename, errfilename, wholefileflag)
end

----------------------------------------------------------------------------------------

local default_pattern_name = "<uninitialized pattern>"
local function make_default_pattern(name)
   return pattern{name=default_pattern_name,
		  peg = lpeg.Cc('Error: no pattern set for engine "' .. name .. '"'),
		  alias = false}
end

engine.create_function =
   function(_new, name, initial_env)
      initial_env = initial_env or common.new_env()
      -- assigning a unique instance id should be part of the recordtype module
      local params = {name=name,
		      env=initial_env,
		      -- setting expression causes pattern to be set
		      expression=default_pattern_name,
		      pattern=make_default_pattern(name),
		      -- setting encoder causes encoder_function to be set
		      encoder=false,
		      encoder_function=name_to_encoder(false),
		      -- functions
		      match=engine_match,
		      match_file=engine_match_file,
		      eval=engine_eval,
		      eval_file=engine_eval_file,
		      configure=engine_configure,
		      inspect=engine_inspect}
      local id = tostring(params):match("0x(.*)") or "id/err"
      params.id = id
      return _new(params)
   end

