---- -*- Mode: Lua; -*- 
----
---- api.lua     Rosie API in Lua
----
---- (c) 2016, Jamie A. Jennings
----

local common = require "common"
local compile = require "compile"
require "engine"
local manifest = require "manifest"
local json = require "cjson"

assert(ROSIE_HOME, "The path to the Rosie installation, ROSIE_HOME, is not set")

--
--    Consolidated Rosie API
--
--      - Managing the environment
--        - Obtain/destroy/ping a Rosie engine
--        - Enable/disable informational logging and warnings to stderr
--            (Need to change QUIET to logging level, and make it a thread-local
--            variable that can be set per invocation of the parser/compiler/etc.)
--
--      - Rosie engine functions
--        - RPL related
--          - RPL statement (incremental compilation)
--          - RPL file compilation
--          - RPL manifest processing
--          - Get a copy of the engine environment
--          - Get identifier definition (human readable, reconstituted)
--
--        - Match related
--          - match pattern against string
--          - match pattern against file
--          - eval pattern against string
--
--        - Post-processing transformations
--          - ???
--
--        - Human interaction / debugging
--          - list patterns
--          - CRUD on color assignments for color output?
--          - help?
--          - debug?

----------------------------------------------------------------------------------------
local api = {VERSION="0.9 alpha"}
----------------------------------------------------------------------------------------

local engine_list = {}

local function arg_error(msg)
   error("Argument error: " .. msg, 0)
end

local function pcall_wrap(f)
   return function(...)
	     return pcall(f, ...)
	  end
end

----------------------------------------------------------------------------------------
-- Managing the environment (engine functions)
----------------------------------------------------------------------------------------

local function delete_engine(id)
   if type(id)~="string" then
      arg_error("engine id not a string")
   end
   engine_list[id] = nil;
   return ""
end

api.delete_engine = pcall_wrap(delete_engine)

local function ping_engine(id)
   if type(id)~="string" then
      arg_error("engine id not a string")
   end
   local en = engine_list[id]
   if en then
      return en.name
   else
      arg_error("invalid engine id")
   end
end

api.ping_engine = pcall_wrap(ping_engine)

local function new_engine(optional_name)	    -- optional manifest? file list? code string?
   if optional_name and (type(optional_name)~="string") then
      arg_error("optional engine name not a string")
   end
   local en = engine(optional_name, compile.new_env())
   if engine_list[en.id] then
      error("Internal error: duplicate engine ids: " .. en.id)
   end
   engine_list[en.id] = en
   return en.id
end

api.new_engine = pcall_wrap(new_engine)

local function engine_from_id(id)
   if type(id)~="string" then
      arg_error("engine id not a string")
   end
   local en = engine_list[id]
   if (not engine.is(en)) then
      arg_error("invalid engine id")
   end
   return en
end

local function get_env(id)
   local en = engine_from_id(id)
   local env = compile.flatten_env(en.env)
   return json.encode(env)
end

api.get_env = pcall_wrap(get_env)

----------------------------------------------------------------------------------------
-- Loading manifests, files, strings
----------------------------------------------------------------------------------------

function api.load_manifest(id, manifest_file)
   local ok, en = pcall(engine_from_id, id)
   if not ok then return false, en; end		    -- en is a message in this case
   local ok, full_path = pcall(common.compute_full_path, manifest_file)
   if not ok then return false, full_path; end	    -- full_path is a message
   local result, msg = manifest.process_manifest(en, full_path)
   return result, msg or ""
end

function api.load_file(id, path)
   -- paths not starting with "." or "/" are interpreted as relative to rosie home directory
   local ok, en = pcall(engine_from_id, id)
   if not ok then return false, en; end		    -- en is a message in this case
   local ok, full_path = pcall(common.compute_full_path, path)
   if not ok then return false, full_path; end	    -- full_path is a message
   local result, msg = compile.compile_file(full_path, en.env)
   return (not (not result)), msg or ""
end

function api.load_string(id, input)
   local ok, en = pcall(engine_from_id, id)
   if not ok then return false, en; end
   local result, msg = compile.compile(input, en.env)
   return (not (not result)), msg or ""
end

-- get a human-readable definition of identifier (reconstituted from its ast)
local function get_definition(engine_id, identifier)
   local en = engine_from_id(engine_id)
   if type(identifier)~="string" then
      arg_error("identifier argument not a string")
   end
   local val = en.env[identifier]
   if not val then
      error("undefined identifier", 0)
   else
      if pattern.is(val) then
	 return common.reconstitute_pattern_definition(identifier, val)
      else
	 error("Internal error: object in environment not a pattern: " .. tostring(val))
      end
   end
end

api.get_definition = pcall_wrap(get_definition)

----------------------------------------------------------------------------------------
-- Matching
----------------------------------------------------------------------------------------

local function match_using_exp(id, pattern_exp, input_text)
   -- returns sucess flag, json match results, and number of unmatched chars at end
   local en = engine_from_id(id)
   if not pattern_exp then arg_error("missing pattern expression"); end
   if not input_text then arg_error("missing input text"); end
   local pat, msg = compile.compile_command_line_expression(pattern_exp, en.env)
   if not pat then error(msg); end
   local result, nextpos = compile.match_peg(pat.peg, input_text)
   if result then
      return json.encode(result), (#input_text - nextpos + 1)
   else
      error("", 0)
   end
end
   
api.match_using_exp = pcall_wrap(match_using_exp)

local function match_set_exp(id, pattern_exp)
   local en = engine_from_id(id)
   if not pattern_exp then arg_error("missing pattern expression"); end
   local pat, msg = compile.compile_command_line_expression(pattern_exp, en.env)
   if not pat then error(msg); end
   en.program = { pat }
   return ""
end

api.match_set_exp = pcall_wrap(match_set_exp)

local function match(id, input_text)
   local en = engine_from_id(id)
   local result, nextpos = en:run(input_text)
   if result then
      return json.encode(result), (#input_text - nextpos + 1)
   else
      error("",0)
   end
end

api.match = pcall_wrap(match)
   
return api



