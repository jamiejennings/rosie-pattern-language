-- -*- Mode: Lua; -*-                                                                             
--
-- process_rpl_file.lua
--
-- © Copyright IBM Corporation 2016, 2017.
-- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
-- AUTHOR: Jamie A. Jennings

assert(ROSIE_ROOT, "The path to the Rosie standard library, ROSIE_ROOT, is not set")

local p = {}

local common = require "common"
local manifest = require "manifest"
local util = require "util"

local function arg_error(msg)
   error("Argument error: " .. msg, 0)
end

function p.load_file(en, path, filetype)
   if not engine.is(en) then arg_error("not an engine: " .. tostring(en)); end
   if type(path)~="string" then arg_error("path not a string: " .. tostring(path)); end
   if filetype=="manifest" then
      -- local full_path, proper_path = common.compute_full_path(manifest_file)
      local ok, messages, full_path = manifest.process_manifest(en, path, ROSIE_ROOT)
      if not ok then error(messages, 0); end
      return common.compact_messages(messages), full_path;
   elseif filetype=="rpl" then
      local full_path, msg = common.compute_full_path(path, nil, ROSIE_ROOT)
      if not full_path then return false, msg; end
      local input, msg = util.readfile(full_path)
      if not input then error(msg, 0); end
      local result, messages = en:load(input)
      if not result then error(messages, 0); end
      return common.compact_messages(messages), full_path
   else
      arg_error("missing or invalid file type argument: " .. tostring(filetype))
   end
end

return p
