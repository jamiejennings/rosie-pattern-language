---- -*- Mode: Lua; -*- 
----
---- manifest.lua     Read a manifest file that tells Rosie which rpl files to compile/load
----
---- (c) 2015, Jamie A. Jennings
----

assert(ROSIE_HOME, "The path to the Rosie installation, ROSIE_HOME, is not set")

local common = require "common"
local compile = require "compile"

local manifest = {}

local mpats = [==[
      -- These patterns define the contents of the Rosie MANIFEST file
      alias blank = ""
      alias comment = "--" .*
      alias unix_path = { {"../" / "./" / "/"}? {{[:alnum:]/[_%!$@:.,~-/] / "\\ "}+ }+  }
      alias windows_path = { {[:alpha:]+ ":"}? {"\\" {![\\?*] .}* }+ }
      path = unix_path / windows_path
      line = comment / (path comment?) / blank
   ]==]

local manifest_engine = engine("manifest", compile.new_env())
compile.compile(mpats, manifest_engine.env)
assert(pattern.is(manifest_engine.env.line))
manifest_engine.program = {compile.compile_command_line_expression('line', manifest_engine.env)}

local function process_manifest_line(en, line)
   local m = manifest_engine:run(line)
   assert(type(m)=="table", "Uncaught error processing manifest file!")
   local name, pos, text, subs, subidx = common.decode_match(m)
   if subidx then
      -- the only sub-match of "line" is "path", because "comment" is an alias
      local name, pos, path = common.decode_match(subs[subidx])
      local filename
      if path:sub(1,1)=="." or path:sub(1,1)=="/" then
	 -- absolute path
	 filename = path
      else
	 -- path relative to ROSIE_HOME
	 filename = ROSIE_HOME .. "/" .. path
      end
      filename = filename:gsub("\\ ", " ")	    -- unescape a space in the name
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
   local success, nextline = pcall(io.lines, manifest_filename)
   if not success then
      local msg = "Error: Cannot open manifest file '" .. manifest_filename
      io.stderr:write(msg, "\n")
      return false, msg
   else
      if not QUIET then
	 io.stderr:write("Reading manifest file: ", manifest_filename, "\n")
      end
      local line, success
      success, line = pcall(nextline)
      if not success then
	 return false, line			    -- e.g. error if a directory
      else
	 while line and success do
	    success, msg = process_manifest_line(en, line)
	    line = nextline()
	 end
	 return success, msg
      end
   end
end

return manifest
