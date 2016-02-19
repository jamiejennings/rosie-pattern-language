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

require "bootstrap"
local common = require "common"
local compile = require "compile"

local mpats = [==[
      -- These patterns define the contents of the Rosie MANIFEST file
      alias blank = ""
      alias comment = "--" .*
      alias validchars = { [:alnum:] / [_%!$@:.,~-] }
      path = { validchars+ {"/" validchars+}* }
      line = comment / (path comment?) / blank
   ]==]

local manifest_engine = engine("manifest", {}, compile.new_env())
compile.compile(mpats, manifest_engine.env)
assert(pattern.is(manifest_engine.env.line))
manifest_engine.program = {compile.compile_command_line_expression('line', manifest_engine.env)}

function process_manifest_line(en, line, dry_run)
--   local m = match('line', line, 1, manifest_engine)
   local m = manifest_engine:run(line)
   assert(type(m)=="table", "Uncaught error processing manifest file!")
   local name, pos, text, subs, subidx = common.decode_match(m)
   if subidx then
      -- the only sub-match of "line" is "path", because "comment" is an alias
      local name, pos, path = common.decode_match(subs[subidx])
      local filename = ROSIE_HOME .. "/" .. path
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
      os.exit(-1)
   end
   if not QUIET then
      io.stderr:write("Reading manifest file: ", manifest_filename, "\n")
   end
   local line = nextline()
   while line do
      process_manifest_line(en, line, dry_run)
      line = nextline()
   end
end

-- process the manifest file, then build a sorted list of all the patterns in the environment.
function do_manifest(en, manifest_file)
   process_manifest(en, manifest_file)
   local pattern_list = {}
   local n = next(en.env)
   while n do
      table.insert(pattern_list, n)
      n = next(en.env, n);
   end
   table.sort(pattern_list)
   return pattern_list
end

