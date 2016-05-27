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
      alias unix_path = { {"../" / "./" / "/"}? {{[:alnum:]/[_%!$@:.,~-/] / "\\ "}+ }+  }
      alias windows_path = { {[:alpha:]+ ":"}? {"\\" {![\\?*] .}* }+ }
      path = unix_path / windows_path
      line = comment / (path comment?) / blank
   ]==]

local manifest_engine = engine("manifest", compile.new_env())
local ok, msg = compile.compile(mpats, manifest_engine.env)
if not ok then error("Internal error: can't compile manifest rpl: " .. msg); end
assert(pattern.is(manifest_engine.env.line))
--local result, msg = compile.compile_command_line_expression('line', manifest_engine.env)
--if not result then error("Internal error: can't compile manifest top level defn: " .. tostring(msg)); end
manifest_engine:configure({ expression = "line", encoder = false })

local function process_manifest_line(en, line)
   local m = manifest_engine:match(line)
   assert(type(m)=="table", "Uncaught error processing manifest file!")
   local name, pos, text, subs = common.decode_match(m)
   if subs then
      -- the only sub-match of "line" is "path", because "comment" is an alias
      local name, pos, path = common.decode_match(subs[1])
      local filename = common.compute_full_path(path)
      if not QUIET then 
	 io.stderr:write("Compiling ", filename, "\n")
      end
      local result, msg = compile.compile_file(filename, en.env)
      return (not (not result)), msg
   else
      return true
   end
end

function manifest.process_manifest(en, manifest_filename)
   assert(engine.is(en))
   local full_path = common.compute_full_path(manifest_filename)
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
   while line and success do
      success, msg = process_manifest_line(en, line)
      line = nextline()
   end
   return success, (success and full_path) or msg
end

return manifest
