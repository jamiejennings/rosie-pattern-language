---- -*- Mode: Lua; -*-                                                                           
----
---- lapi.lua     Rosie API in Lua, for Lua programs
----
---- © Copyright IBM Corporation 2016.
---- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
---- AUTHOR: Jamie A. Jennings

local common = require "common"
local compile = require "compile"
require "engine"
local manifest = require "manifest"
local json = require "cjson"
local eval = require "eval"
require "color-output"

-- temporary:
require "grep"
lpeg = require "lpeg"
Cp = lpeg.Cp

assert(ROSIE_HOME, "The path to the Rosie installation, ROSIE_HOME, is not set")

--    Consolidated Rosie API
--
--      - Managing the environment
--        + Obtain/destroy/ping a Rosie engine
--        - Enable/disable informational logging and warnings to stderr
--            (Need to change QUIET to logging level, and make it a thread-local
--            variable that can be set per invocation of the parser/compiler/etc.)
--
--      + Rosie engine functions
--        + RPL related
--          + RPL statement (incremental compilation)
--          + RPL file compilation
--          + RPL manifest processing
--          + Get a copy of the engine environment
--          + Get identifier definition (human readable, reconstituted)
--
--        + Match related
--          + match pattern against string
--          + match pattern against file
--          + eval pattern against string
--          + eval pattern against file
--
--        - Human interaction / debugging
--          - CRUD on color assignments for color output?


----------------------------------------------------------------------------------------
local lapi = {API_VERSION = "0.96 alpha",	    -- api version
              RPL_VERSION = "0.96",		    -- language version
              ROSIE_VERSION = ROSIE_VERSION,	    -- code revision level
              ROSIE_HOME = ROSIE_HOME		    -- install directory
}
----------------------------------------------------------------------------------------

local function arg_error(msg)
   error("Argument error: " .. msg, 0)
end

function lapi.version(verbose)
   if (not verbose) then
      return lapi.API_VERSION
   else
      local info = {}
      for k,v in pairs(lapi) do
	 if (type(k)=="string") and (type(v)=="string") then
	    info[k] = v
	 end
      end -- loop
      return info
   end -- switch on verbose
end

----------------------------------------------------------------------------------------
-- Managing the environment (engine functions)
----------------------------------------------------------------------------------------

function lapi.inspect_engine(en)
   if not engine.is(en) then arg_error("not an engine: " .. tostring(en)); end
   local name, config = en:inspect()
   config.encoder = encoder_to_name(config.encoder)
   return name, config
end

function lapi.new_engine(optional_name)	    -- optional manifest? file list? code string?
   optional_name = (optional_name and tostring(optional_name)) or "<anonymous>"
   return engine(optional_name, compile.new_env())
end

function lapi.get_env(en)
   if not engine.is(en) then arg_error("not an engine: " .. tostring(en)); end
   return compile.flatten_env(en.env)
end

function lapi.clear_env(en)
   if not engine.is(en) then arg_error("not an engine: " .. tostring(en)); end
   en.env = compile.new_env()
end

----------------------------------------------------------------------------------------
-- Loading manifests, files, strings
----------------------------------------------------------------------------------------

function lapi.load_manifest(en, manifest_file)
   if not engine.is(en) then arg_error("not an engine: " .. tostring(en)); end
   local ok, full_path = pcall(common.compute_full_path, manifest_file)
   if not ok then return false, full_path; end	    -- full_path is a message
   local result, msg = manifest.process_manifest(en, full_path)
   if result then
      return true, full_path
   else
      return false, msg
   end
end

function lapi.load_file(en, path)
   if not engine.is(en) then arg_error("not an engine: " .. tostring(en)); end
   local full_path = common.compute_full_path(path)
   local result, msg = compile.compile_file(full_path, en.env)
   if result then
      return true, full_path
   else
      return false, msg
   end
end

function lapi.load_string(en, input)
   if not engine.is(en) then arg_error("not an engine: " .. tostring(en)); end
   local ok, msg = compile.compile(input, en.env)
   if ok then
      return true, msg				    -- msg may contain warnings
   else 
      return false, msg
   end
end

-- get a human-readable definition of identifier (reconstituted from its ast)
function lapi.get_definition(en, identifier)
   if not engine.is(en) then arg_error("not an engine: " .. tostring(en)); end
   local val = en.env[identifier]
   if not val then
      return false, "undefined identifier: " .. tostring(identifier)
   else
      if pattern.is(val) then
	 return common.reconstitute_pattern_definition(identifier, val)
      else
	 error("Internal error: object in environment not a pattern: " .. tostring(val))
      end
   end
end

----------------------------------------------------------------------------------------
-- Matching
----------------------------------------------------------------------------------------

local encoder_table =
   {json = json.encode,
    color = color_string_from_leaf_nodes,
    text = common.match_to_text
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

function lapi.configure(en, c)
   if not engine.is(en) then arg_error("not an engine: " .. tostring(en)); end
   if type(c)~="table" then
      arg_error("configuration not a table: " .. tostring(c)); end
   if c.encoder then
      local encoder_function = name_to_encoder(c.encoder)
      if not encoder_function then
	 arg_error("invalid encoder: " .. tostring(c.encoder))
      else
	 c.encoder_function = encoder_function
      end
   end
   return pcall(en.configure, en, c)
end

----------------------------------------------------------------------------------------
-- Note: The match and eval functions do not check their arguments, which gives a small
-- boost in performance.  A Lua program which provides bad arguments to these functions
-- will be interrupted with a call to error().  The external API does more argument
-- checking. 

function lapi.match(en, input_text, start)
   local result, nextpos = en:match(input_text, start)
   return result, (#input_text - nextpos + 1)
end

function lapi.match_file(en, infilename, outfilename, errfilename)
   return en:match_file(infilename, outfilename, errfilename)
end

function lapi.eval(en, input_text, start)
   local result, nextpos, trace = en:eval(input_text, start)
   local leftover = 0;
   if nextpos then leftover = (#input_text - nextpos + 1); end
   return result, leftover, trace
end

function lapi.eval_file(en, infilename, outfilename, errfilename)
   return en:eval_file(infilename, outfilename, errfilename)
end

----------------------------------------------------------------------------------------

function lapi.set_match_exp_grep_TEMPORARY(en, pattern_exp, encoder_name)
   if not engine.is(en) then arg_error("not an engine: " .. tostring(en)); end
   if type(pattern_exp)~="string" then arg_error("pattern expression not a string"); end
   return lapi.configure(en, { pattern = pattern_EXP_to_grep_pattern(pattern_exp, en.env),
			       encoder = encoder_name });
end   

return lapi
