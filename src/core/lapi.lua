---- -*- Mode: Lua; -*-                                                                           
----
---- lapi.lua     Rosie API in Lua, for Lua programs
----
---- © Copyright IBM Corporation 2016.
---- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
---- AUTHOR: Jamie A. Jennings

local util = require "util"
local common = require "common"
local pattern = common.pattern
local compile = require "compile"
local parse = require "parse"
local engine = require "engine"
local manifest = require "manifest"
local eval = require "eval"
local co = require "color-output"

-- temporary:
local grep = require "grep"
local lpeg = require "lpeg"
local Cp = lpeg.Cp

assert(ROSIE_HOME, "The path to the Rosie installation, ROSIE_HOME, is not set")

local function reconstitute_pattern_definition(id, p)
   if p then
      return ( --((p.alias and "alias ") or "") .. id .. " = " ..
	       ((p.original_ast and parse.reveal_ast(p.original_ast)) or
	        (p.ast and parse.reveal_ast(p.ast)) or
	      "// built-in RPL pattern //"))
   else
      error("undefined identifier: " .. id)
   end
end

----------------------------------------------------------------------------------------
local lapi = {}

--lapi.home = false;				    -- set to ROSIE_HOME after loading
lapi.home = ROSIE_HOME;

local function arg_error(msg)
   error("Argument error: " .. msg, 0)
end

----------------------------------------------------------------------------------------
-- Managing the environment (engine functions)
----------------------------------------------------------------------------------------

function lapi.inspect_engine(en)
   if not engine.is(en) then arg_error("not an engine: " .. tostring(en)); end
   return en:inspect()
end

function lapi.new_engine(optional_cfg)
   optional_cfg = optional_cfg or {}
   if not optional_cfg.name then optional_cfg.name = "<anonymous>"; end
   local en = engine.new(optional_cfg.name, common.new_env())
   local ok, msg = en:configure(optional_cfg)
   return en, ok, msg
end

-- get a human-readable definition of an identifier (reconstituted from its ast), or of the entire
-- environment 
function lapi.get_environment(en, identifier)
   if not engine.is(en) then arg_error("not an engine: " .. tostring(en)); end
   return en:lookup(identifier)
end

function lapi.clear_environment(en, identifier)
   if not engine.is(en) then arg_error("not an engine: " .. tostring(en)); end
   if identifier then
      if en.env[identifier] then
	 en.env[identifier] = nil
	 return true
      else
	 return false
      end
   else
      en.env = common.new_env()
      return true
   end -- if identifier arg supplied
end

----------------------------------------------------------------------------------------
-- Loading manifests, files, strings
----------------------------------------------------------------------------------------

function lapi.load_manifest(en, full_path)
   if not engine.is(en) then arg_error("not an engine: " .. tostring(en)); end
   -- local full_path, proper_path = common.compute_full_path(manifest_file)
   local ok, messages, full_path = manifest.process_manifest(en, full_path, lapi.home)
   return ok, common.compact_messages(messages), full_path
end

function lapi.load_file(en, path)
   if not engine.is(en) then arg_error("not an engine: " .. tostring(en)); end
   if type(path)~="string" then arg_error("path not a string: " .. tostring(path)); end
   local full_path, msg = common.compute_full_path(path, nil, lapi.home)
   if not full_path then return false, msg; end
   local input, msg = util.readfile(full_path)
   if not input then return false, msg; end
   local result, messages = compile.compile_source(input, en.env)
   return result, common.compact_messages(messages), full_path
end

function lapi.load_string(en, input)
   if not engine.is(en) then arg_error("not an engine: " .. tostring(en)); end
   local results, messages = compile.compile_source(input, en.env)
   return results, common.compact_messages(messages)
end

function lapi.configure_engine(en, c)
   if not engine.is(en) then arg_error("not an engine: " .. tostring(en)); end
   if type(c)~="table" then
      arg_error("configuration not a table: " .. tostring(c)); end
   return en:configure(c)
end

----------------------------------------------------------------------------------------
-- Matching
----------------------------------------------------------------------------------------

-- Note: The match and eval functions do not check their arguments, which gives a small
-- boost in performance.  A Lua program which provides bad arguments to these functions
-- will be interrupted with a call to error().  The external API does more argument
-- checking. 

function lapi.match(en, expression, input_text, start)
   local result, nextpos = en:match(expression, input_text, start)
   return result, (#input_text - nextpos + 1)
end

function lapi.match_file(en, infilename, outfilename, errfilename, wholefileflag)
   return en:match_file(infilename, outfilename, errfilename, wholefileflag)
end

function lapi.eval(en, input_text, start)
   local result, nextpos, trace = en:eval(input_text, start)
   local leftover = 0;
   if nextpos then leftover = (#input_text - nextpos + 1); end
   return result, leftover, trace
end

function lapi.eval_file(en, infilename, outfilename, errfilename, wholefileflag)
   return en:eval_file(infilename, outfilename, errfilename, wholefileflag)
end

----------------------------------------------------------------------------------------

function lapi.set_match_exp_grep_TEMPORARY(en, pattern_exp, encoder_name)
   if not engine.is(en) then arg_error("not an engine: " .. tostring(en)); end
   if type(pattern_exp)~="string" then arg_error("pattern expression not a string"); end
   local pat, msg = grep.pattern_EXP_to_grep_pattern(pattern_exp, en.env);
   if pattern.is(pat) then
      en.expression = "grep(" .. pattern_exp .. ")"
      en.pattern = pat
      return lapi.configure_engine(en, {encode=encoder_name})
   else
      arg_error(msg)
   end
end


return lapi
