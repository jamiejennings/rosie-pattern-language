---- -*- Mode: Lua; -*-                                                                           
----
---- manifest.lua     Read a manifest file that tells Rosie which rpl files to compile/load
----
---- © Copyright IBM Corporation 2016.
---- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
---- AUTHOR: Jamie A. Jennings


assert(ROSIE_HOME, "The path to the Rosie installation, ROSIE_HOME, is not set")

local common = require "common"
local compile = require "compile"

local manifest = {}

local mpats = [==[
      -- These patterns define the contents of the Rosie MANIFEST file
      alias blank = {""}
      alias comment = {"--" .*}
      path = {![[:space:]] {"\\ " / .}}+	    -- escaped spaces allowed
      line = comment / (path comment?) / blank
   ]==]

local manifest_engine = engine("manifest")
local ok, msg = compile.compile_source(mpats, manifest_engine.env)
if not ok then error("Internal error: can't compile manifest rpl: " .. msg); end
assert(pattern.is(manifest_engine.env.line))
manifest_engine:configure({expression="line", encoder=false})

local function process_manifest_line(en, line, manifest_path)
   local m = manifest_engine:match(line)
   assert(type(m)=="table", "Uncaught error processing manifest file!")
   local name, pos, text, subs = common.decode_match(m)
   if subs then
      -- the only sub-match of "line" is "path", because "comment" is an alias
      local name, pos, path = common.decode_match(subs[1])
      local filename, msg = common.compute_full_path(path, manifest_path)
      if not filename then return false, msg; end
      if not QUIET then 
	 io.stderr:write("Compiling ", filename, "\n")
      end
      local input, msg = util.readfile(filename)
      if not input then return false, msg; end
      local results, messages = compile.compile_source(input, en.env)
      return (not (not results)), messages
   else
      return true				    -- no file name on this line
   end
end

function manifest.process_manifest(en, manifest_filename)
   assert(engine.is(en))
   local full_path, manifest_path = common.compute_full_path(manifest_filename)
   if not full_path then return false, manifest_path; end
   local success, nextline = pcall(io.lines, full_path)
   if not success then
      local msg = 'Error opening manifest file "' .. full_path .. '"'
      return false, msg
   end
   if not QUIET then
      io.stderr:write("Reading manifest file ", full_path, "\n")
   end
   local success, line = pcall(nextline)
   if not success then
      -- e.g. error if a directory
      local msg = 'Error reading manifest file "' .. full_path .. '": ' .. line	
      return false, msg
   end
   local all_messages = {}
   while line and success do
      success, messages = process_manifest_line(en, line, manifest_path)
      if not success then return success, messages; end
      if messages then
	 for _, msg in ipairs(messages) do
	    if msg then table.insert(all_messages, m); end;
	 end -- for
      end
      line = nextline()
   end -- while line and success
   return success, all_messages, full_path
end

return manifest
