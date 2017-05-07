-- -*- Mode: Lua; -*-                                                                             
--
-- process_rpl_file.lua
--
-- © Copyright IBM Corporation 2016, 2017.
-- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
-- AUTHOR: Jamie A. Jennings

assert(ROSIE_LIB, "The path to the Rosie standard library (ROSIE_LIB) is not set")

local p = {}

local common = require "common"
local util = require "util"

local function arg_error(msg)
   error("Argument error: " .. msg, 0)
end

function p.load_file(en, path)
   if not engine.is(en) then arg_error("not an engine: " .. tostring(en)); end
   if type(path)~="string" then arg_error("path not a string: " .. tostring(path)); end
--   local full_path, msg = common.compute_full_path(path, nil, ROSIE_LIB)
--   if not full_path then return false, msg; end
   local full_path = path
   
   local input, msg = util.readfile(full_path)
   if not input then error(msg, 0); end
   local result, msg = en:load(input)
   if not result then error(msg, 0); end
   -- normal return from 'en:load()' is a table of warnings (possibly empty)
   return common.compact_messages(result), full_path
end

return p
