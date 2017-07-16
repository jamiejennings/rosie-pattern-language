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
cli_match = assert(rosie.import("command-match"), "failed to open command-match package")
cli_test = assert(rosie.import("command-test"), "failed to open command-test package")
cli_common = assert(rosie.import("command-common"), "failed to open command-common package")

parser = argparser.create(rosie)

function create_cl_engine(args)
   CL_ENGINE = rosie.engine.new("command line engine")
   if (not CL_ENGINE) then error("Internal error: could not obtain new engine: " .. msg); end
   if args.libpath then
      CL_ENGINE.searchpath = args.libpath
   else
      CL_ENGINE.searchpath = rosie.info().ROSIE_PATH
   end
end

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

local function run(args)
   if args.verbose then ROSIE_VERBOSE = true; end

   ok, msg = pcall(create_cl_engine, args)
   if not ok then print("Error in cli when creating cli engine: " .. msg); end

   local en = CL_ENGINE
   
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
	 print(parser:get_help())
      end
      os.exit()
   end
   
   if args.verbose then greeting(); end

   if args.command == "test" then
      -- lightweight pattern test framework does a custom setup:
      -- for each file being tested
      --     get a fresh engine and load any rpl files or rpl strings
      --     load the file being tested
      --     call the test procedure
      cli_test.setup(en)
      local total_failures, total_tests = 0, 0
      for _, fn in ipairs(args.filenames) do
	 local failures, total = cli_test.run(rosie, en, args, fn)
	 total_failures = total_failures + failures
	 total_tests = total_tests + total
      end
      if #args.filenames > 1 then
	 if total_failures~=0 then
	    print("Total of " .. tostring(total_failures) ..
	       " tests failed out of " .. tostring(total_tests) .. " attempted")
	 else
	    print("All " .. tostring(total_tests) .. " tests passed")
	 end
      end
      os.exit((total_failures==0) and 0 or -1)
   end
   
   local compiled_pattern = cli_common.setup_engine(en, args);

   if args.command == "list" then
      if not args.verbose then greeting(); end
      -- local name, properties = en:lookup(args.filter)
      -- if properties.type=="package" then ...
      local env = en:lookup()
      ui.print_env(env, args.filter)
      os.exit()
   elseif args.command == "repl" then
      local repl_mod = mod.import("repl", rosie_mod)
      if not args.verbose then greeting(); end
      repl_mod.repl(en)
      os.exit()
   else
      for _,fn in ipairs(args.filename) do
	 cli_match.process_pattern_against_file(rosie, en, args, compiled_pattern, fn)
      end
   end -- if command is list or repl or other
end -- function run

local args = parser:parse()
run(args)
