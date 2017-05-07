---- -*- Mode: Lua; -*-
----
---- cli.lua
----
---- © Copyright IBM Corporation 2016, 2017.
---- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
---- AUTHOR: Jamie A. Jennings

-- This code is fed to the lua interpreter by a shell script.  The script supplies the first two
-- args (ROSIE_HOME and ROSIE_DEV) before the user-supplied Rosie CLI args.  ROSIE_HOME is the
-- full path to a Rosie install directory, and ROSIE_DEV is the string "true" if the CLI was
-- launched in "development mode", which drops into a Lua repl after loading Rosie:
--     "-D" is an 'undocumented' command line switch which, when it appears as the first command
--     line argument to the Rosie run script, will launch Rosie in development mode.  The code
--     below does not need to process that switch.

ROSIE_HOME = arg[1]
ROSIE_DEV = (arg[2]=="true")

if not ROSIE_HOME then
	io.stderr:write("Installation error: Lua variable ROSIE_HOME is not defined\n")
	os.exit(-2)
end

-- Reconstruct the command line using all the arg information available.  For readability, we
-- replace instances of ROSIE_HOME with the string "ROSIE_HOME" at the start of each arg.
local s=0; while arg[s] do s=s-1; end; s=s+1	                     -- Find first arg
local function munge_arg(a)                                          -- Replace
   local s, e = a:find(ROSIE_HOME, 1, true)
   if s then return "ROSIE_HOME" .. a:sub(e+1); else return a; end
end
local str=""; for i=s,#arg do str=str..munge_arg(arg[i]).." "; end   -- Assemble string

ROSIE_COMMAND = str:sub(1,-1)                                        -- Remove trailing space

-- Shift args by 2, to remove ROSIE_HOME and ROSIE_DEV
table.move(arg, 3, #arg, 1); arg[#arg-1]=nil; arg[#arg]=nil;

-- Load rosie
rosie = dofile(ROSIE_HOME .. "/rosie.lua", "t")
package.loaded.rosie = rosie

ROSIE_VERSION = rosie.info().ROSIE_VERSION

engine_module = assert(rosie.import("engine_module"), "failed to load engine_module package")
common = assert(rosie.import("common"), "failed to open common package")
lpeg = assert(rosie.import("lpeg"), "failed to open lpeg package")

ui = assert(rosie.import("ui"), "failed to open ui package")
argparser = assert(rosie.import("command-parser"), "failed to load command-parser package")
match = assert(rosie.import("command-match"), "failed to open command-match package")
test = assert(rosie.import("command-test"), "failed to open command-test package")

parser = argparser.create(rosie)

function create_cl_engine()
   CL_ENGINE = rosie.engine.new("command line engine")
   if (not CL_ENGINE) then error("Internal error: could not obtain new engine: " .. msg); end
end

ok, msg = pcall(create_cl_engine)
if not ok then print("Error in cli when creating cli engine: " .. msg); end

local function print_rosie_info()
   local function printf(fmt, ...)
      print(string.format(fmt, ...))
   end
   local fmt = "%20s = %s"
   for _,info in ipairs(rosie.info()) do printf(fmt, info.name, info.value); end
   local log = io.open(ROSIE_HOME .. "/build.log", "r")
   if log then
      print()
      local line = log:read("l")
      while line do
	 local name, val = line:match('([^ ]+) (.*)')
	 printf(fmt, name, val)
	 line = log:read("l")
      end
   end
end

local function greeting()
   io.write("Rosie " .. ROSIE_VERSION .. "\n")
end

local function load_string(en, input)
   local ok, results, messages = pcall(en.load, en, input)
   if not ok then
      if ROSIE_DEV then error(results)
      else io.write("Cannot load rpl: \n", results); os.exit(-1); end
   end
   return results, messages
end

local function setup_engine(args)
   -- (1a) Load whatever is specified in ~/.rosierc ???


   -- (1b) Load an rpl file
   if args.rpls then
      for _,file in pairs(args.rpls) do
	 if args.verbose then
	    io.stdout:write("Compiling additional file ", file, "\n")
	 end
	 local success, msg = pcall(rosie.file.load, CL_ENGINE, file, "rpl")
	 if not success then
	    io.stdout:write(msg, "\n")
	    os.exit(-4)
	 end
      end
   end

   -- (1c) Load an rpl string from the command line
   if args.statements then
      for _,stm in pairs(args.statements) do
	 if args.verbose then
	    io.stdout:write(string.format("Compiling additional rpl code %q\n", stm))
	 end
	 local success, msg = load_string(CL_ENGINE, stm)
	 if not success then
	    io.stdout:write(msg, "\n")
	    os.exit(-4)
	 end
      end
   end
   -- (2) Compile the expression
   if args.pattern then
      local expression
      if args.fixed_strings then
	 expression = '"' .. args.pattern:gsub('"', '\\"') .. '"' -- FUTURE: rosie.expr.literal(arg[2])
      else
	 expression = args.pattern
      end
      local flavor = (args.command=="grep") and "search" or "match"
      local ok, msgs
      ok, compiled_pattern, msgs = pcall(CL_ENGINE.compile, CL_ENGINE, expression, flavor)
      if not ok then
	 io.stdout:write(compiled_pattern, "\n")
	 os.exit(-4)
      elseif not compiled_pattern then
	 io.stdout:write(table.concat(msgs, '\n'), '\n')
	 os.exit(-4)
      end
   end
end

local function run(args)
   if args.verbose then rosie.setmode("verbose"); end
   if ROSIE_DEV then rosie.setmode("dev"); end

   if not args.command then
      if ROSIE_DEV then greeting(); return
      else
	 print("Usage: rosie command [options] pattern file [...])")
	 os.exit(-1)
      end
   end
   if (args.command=="info") or (args.command=="help") then
      if args.command=="info" then
	 print_rosie_info()
      else
	 print(parse:get_help())
      end
      os.exit()
   end
   
   if args.verbose then greeting(); end

   if args.command == "test" then
      -- lightweight pattern test framework does a custom setup:
      -- first, set up the rosie CLI engine and automatically load the file being tested (after
      -- loading all the other stuff per the other command line args and defaults)
      if not args.rpls then
	 args.rpls = { args.filename }
      else
	 table.insert(args.rpls, args.filename)
      end
      setup_engine(args);
      test.setup_and_run(rosie, CL_ENGINE, args);   -- TODO: right now, this calls os.exit()
   end
   
   setup_engine(args);

   if args.command == "list" then
      if not args.verbose then greeting(); end
      local env = CL_ENGINE:lookup()
      ui.print_env(env, args.filter)
      os.exit()
   end

   if args.command == "repl" then
      repl_mod = mod.import("repl", rosie_mod)
      if not args.verbose then greeting(); end
      repl_mod.repl(CL_ENGINE)
      os.exit()
   end

   for _,fn in ipairs(args.filename) do
      match.process_pattern_against_file(rosie, CL_ENGINE, args, compiled_pattern, fn)
   end
end -- function run

local args = parser:parse()
run(args)
