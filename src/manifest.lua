---- -*- Mode: Lua; -*- 
----
---- manifest.lua     Read a manifest file that tells Rosie which rpl files to compile/load
----
---- (c) 2015, Jamie A. Jennings
----

-- This lua script must be called with the variable ROSIE_HOME set to be the full directory of the
-- rosie installation (not a relative path such as one starting with . or ..)
--
-- E.g. ROSIE_HOME="/Users/jjennings/Work/Dev/rosie-dev"

assert(ROSIE_HOME, "The path to the Rosie installation, ROSIE_HOME, is not set")

-- ROSIE_HOME and ROSIE_VERSION are set by dev.lua

local common = require "common"
local compile = require "compile"

local mpats = [==[
      -- These patterns define the contents of the Rosie MANIFEST file
      alias blank = ""
      alias comment = "--" .*
      alias unix_path = { {"../" / "./" / "/"}? {{[:alnum:]/[_%!$@:.,~-/] / "\\ "}+ }+  }
      alias windows_path = { {[:alpha:]+ ":"}? {"\\" {![\\?*] .}* }+ }
      path = unix_path / windows_path
      line = comment / (path comment?) / blank
   ]==]

local manifest_engine = engine("manifest", {}, compile.new_env())
compile.compile(mpats, manifest_engine.env)
assert(pattern.is(manifest_engine.env.line))
manifest_engine.program = {compile.compile_command_line_expression('line', manifest_engine.env)}

function process_manifest_line(en, line, dry_run)
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
      if not dry_run then compile.compile_file(filename, en.env); end
   end
end

function process_manifest(en, manifest_filename, dry_run)
   local success, nextline = pcall(io.lines, manifest_filename)
   if not success then
      io.stderr:write("Error: Cannot open manifest file '", manifest_filename, "'\n")
   else
      if not QUIET then
	 io.stderr:write("Reading manifest file: ", manifest_filename, "\n")
      end
      local line = nextline()
      while line do
	 process_manifest_line(en, line, dry_run)
	 line = nextline()
      end
   end
end

