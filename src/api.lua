---- -*- Mode: Lua; -*-                                                                           
----
---- api.lua     Rosie API in Lua
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

--
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
-- 

----------------------------------------------------------------------------------------
local api = {VERSION="0.96 alpha"}
----------------------------------------------------------------------------------------

local engine_list = {}

local function arg_error(msg)
   error("Argument error: " .. msg, 0)
end

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

local function inspect_engine(id)
   local en = engine_from_id(id)
   local name, config = en:inspect()
   return name, json.encode(config)
end

api.inspect_engine = pcall_wrap(inspect_engine)

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

local function get_env(id)
   local en = engine_from_id(id)
   local env = compile.flatten_env(en.env)
   return json.encode(env)
end

api.get_env = pcall_wrap(get_env)

local function clear_env(id)
   local en = engine_from_id(id)
   en.env = compile.new_env()
   return ""
end

api.clear_env = pcall_wrap(clear_env)

----------------------------------------------------------------------------------------
-- Loading manifests, files, strings
----------------------------------------------------------------------------------------

function api.load_manifest(id, manifest_file)
   local ok, en = pcall(engine_from_id, id)
   if not ok then return false, en; end		    -- en is a message in this case
   local ok, full_path = pcall(common.compute_full_path, manifest_file)
   if not ok then return false, full_path; end	    -- full_path is a message
   local result, msg = manifest.process_manifest(en, full_path)
   if result then
      return true, full_path
   else
      return false, msg
   end
end

function api.load_file(id, path)
   -- paths not starting with "." or "/" are interpreted as relative to rosie home directory
   local ok, en = pcall(engine_from_id, id)
   if not ok then return false, en; end		    -- en is a message in this case
   local ok, full_path = pcall(common.compute_full_path, path)
   if not ok then return false, full_path; end	    -- full_path is a message
   local result, msg = compile.compile_file(full_path, en.env)
   if result then
      return true, full_path
   else
      return false, msg
   end
end

function api.load_string(id, input)
   local ok, en = pcall(engine_from_id, id)
   if not ok then return false, en; end
   local ok, msg = compile.compile(input, en.env)
   if ok then
      return true, ""
   else 
      return false, msg
   end
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

local function configure(id, c_string)
   local en = engine_from_id(id)
   if type(c_string)~="string" then
      arg_error("configuration not a (JSON) string: " .. tostring(c_string)); end
   local c = json.decode(c_string)
   if c.encoder == "json" then
      c.encoder = json.encode;
   elseif c.encoder == "color" then
      c.encoder = color_string_from_leaf_nodes;
   elseif c.encoder == "text" then
      c.encoder = function(t) local k,v = next(t); assert(type(v)=="table"); return (v and v.text) or ""; end
   else
      arg_error("invalid encoder: " .. tostring(c.encoder));
   end
   en:configure(c)
   return ""
end

api.configure = pcall_wrap(configure)
   
local function match(id, input_text, start)
   local en = engine_from_id(id)
   if type(input_text)~="string" then arg_error("input text not a string"); end
   local result, nextpos = en:match(input_text, start)
   if result then
      return result, (#input_text - nextpos + 1)
   else
      return false, 0
   end
end

api.match = pcall_wrap(match)

local function match_file(id, infilename, outfilename, errfilename)
   local en = engine_from_id(id)
   return en:match_file(infilename, outfilename, errfilename)
end

api.match_file = pcall_wrap(match_file)

local function eval_(id, input_text, start)
   local en = engine_from_id(id)
   if type(input_text)~="string" then arg_error("input text not a string"); end
   local result, nextpos, trace = en:eval(input_text, start)
   local leftover = 0;
   if nextpos then leftover = (#input_text - nextpos + 1); end
   return result, leftover, trace
end

api.eval = pcall_wrap(eval_)

local function eval_file(id, infilename, outfilename, errfilename)
   local en = engine_from_id(id)
   return en:eval_file(infilename, outfilename, errfilename)
end

api.eval_file = pcall_wrap(eval_file)

local function set_match_exp_grep_TEMPORARY(id, pattern_exp)
   local en = engine_from_id(id)
   if type(pattern_exp)~="string" then arg_error("pattern expression not a string"); end
   en:configure({ pattern = pattern_EXP_to_grep_pattern(pattern_exp, en.env) })
   return ""
end   

api.set_match_exp_grep_TEMPORARY = pcall_wrap(set_match_exp_grep_TEMPORARY)

return api
