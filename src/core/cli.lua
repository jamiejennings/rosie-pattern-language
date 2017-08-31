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

ROSIE_COMMAND = arg[1]
ROSIE_HOME = arg[2]
ROSIE_DEV = (arg[3]=="true")

if not ROSIE_HOME then
	io.stderr:write("Installation error: Lua variable ROSIE_HOME is not defined\n")
	os.exit(-2)
end

-- Reconstruct the command line using all the arg information available.  For readability, we
-- replace instances of ROSIE_HOME with the string "ROSIE_HOME" at the start of each arg.
-- local s=0; while arg[s] do s=s-1; end; s=s+1	                     -- Find first arg
-- local function munge_arg(a)                                          -- Replace
--    local s, e = a:find(ROSIE_HOME, 1, true)
--    if s then return "ROSIE_HOME" .. a:sub(e+1); else return a; end
-- end
-- local str=""; for i=s,#arg do str=str..munge_arg(arg[i]).." "; end   -- Assemble string

-- ROSIE_COMMAND = str:sub(1,-1)                                        -- Remove trailing space

-- Shift args, to remove n args: ROSIE_COMMAND, ROSIE_HOME and ROSIE_DEV
local n = 3
table.move(arg, n+1, #arg, 1); for i=#arg-n+1, #arg do arg[i]=nil; end

-- Load rosie
rosie = dofile(ROSIE_HOME .. "/rosie.lua", "t")
package.loaded.rosie = rosie

ROSIE_VERSION = rosie.info().ROSIE_VERSION

engine_module = assert(rosie.import("engine_module"), "failed to load engine_module package")
common = assert(rosie.import("common"), "failed to open common package")
lpeg = assert(rosie.import("lpeg"), "failed to open lpeg package")

ui = assert(rosie.import("ui"), "failed to open ui package")
argparser = assert(rosie.import("cli-parser"), "failed to load cli parser package")
cli_match = assert(rosie.import("cli-match"), "failed to open cli match package")
cli_test = assert(rosie.import("cli-test-command"), "failed to open cli test package")
cli_common = assert(rosie.import("cli-common"), "failed to open cli common package")
environment = assert(rosie.import("environment"), "failed to open environment package")

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
   if not ok then print("Error when creating cli engine: " .. msg); os.exit(-1); end

   local en = CL_ENGINE
   
   if not args.command then
      if ROSIE_DEV then greeting(); return
      else
	 print("Usage: rosie command [options] pattern file [...])")
	 os.exit(-1)
      end
   end
   if (args.command=="config") then
      print_rosie_info()
      os.exit()
   elseif (args.command=="help") then
      print(parser:get_help())
      os.exit()
   end
   
   if args.verbose then greeting(); end

   -- TODO:
   -- (1) expose plain parser (with/without ambient cooking) at engine/compiler level
   -- (2) expose macro expander at engine/comiler level
   -- (3) expose a print routine for violations
   
   if args.command == "expand" then
      print("Expression: ", args.expression)
      local common = assert(rosie.env.common)			    -- TODO: MOVE THIS!
      local ast = assert(rosie.env.ast)				    -- TODO: MOVE THIS!
      local expand = assert(rosie.env.expand)			    -- TODO: MOVE THIS!
      local violation = assert(rosie.env.violation)		    -- TODO: MOVE THIS!
      local errs = {}
      local a = CL_ENGINE.compiler.parse_expression(common.source.new{text=args.expression}, errs)
      if not a then
	 for _,e in ipairs(errs) do print(violation.tostring(e)) end
	 os.exit(-1)
      end
      print("Parses as: ", ast.tostring(a, true))
      a = ast.ambient_cook_exp(a)
      print("At top level: ", ast.tostring(a, true))
      local aa = expand.expression(a, CL_ENGINE.env, errs)
      if not aa then
	 for _,e in ipairs(errs) do print(violation.tostring(e)) end
	 os.exit(-1)
      end
      print("Expands to: ", ast.tostring(aa, true))
      os.exit()
   end
   
   if args.command == "test" then
      -- lightweight pattern test framework does a custom setup:
      -- for each file being tested
      --     get a fresh engine and load any rpl files or rpl strings
      --     load the file being tested
      --     call the test procedure
      cli_test.setup(en)
      local total_failures, total_tests = 0, 0
      local total_files, total_compiled = 0, 0
      for _, fn in ipairs(args.filenames) do
	 local ok, failures, total = cli_test.run(rosie, en, args, fn)
	 total_files = total_files + 1
	 if ok then total_compiled = total_compiled + 1; end
	 total_failures = total_failures + failures
	 total_tests = total_tests + total
      end
      if args.verbose and (#args.filenames > 1) then
	 print("TOTALS:")
	 io.stdout:write(tostring(#args.filenames), " files, ")
	 if total_files == total_compiled then
	    io.stdout:write("all compiled successfully\n")
	 else
	    io.stdout:write(tostring(total_files-total_compiled), " failed to compile\n")
	 end
	 io.stdout:write(tostring(total_tests), " tests attempted, ")
	 if total_failures~=0 then
	    io.stdout:write(tostring(total_failures), " tests failed")
	 else
	    io.stdout:write("all " .. tostring(total_tests) .. " tests passed\n")
	 end
      end
      if ((total_files-total_compiled) > 0) or (total_failures > 0) then
	 os.exit(-1)
      else
	 os.exit(0)
      end
   end
   
   local compiled_pattern = cli_common.setup_engine(en, args);

   if args.command == "list" then
      if not args.verbose then greeting(); end
      assert(args.filter)			    -- default is "*"
      local pkgname, localname = common.split_id(args.filter)
      if not pkgname then
	 local tbl = environment.exported_bindings(en.env)
	 for k,v in pairs(tbl) do tbl[k] = ui.properties(k,v); end
	 ui.print_env(tbl, localname)
	 os.exit()
      else
	 local pkgenv = en.env:lookup(pkgname)
	 if pkgenv then
	    local props = ui.properties(pkgname, pkgenv)
	    if props.type=="package" then
	       print("Package " .. pkgname)
	       local tbl = environment.exported_bindings(pkgenv)
	       for k,v in pairs(tbl) do tbl[k] = ui.properties(k,v); end
	       ui.print_env(tbl, localname)
	       os.exit()
	    else
	       print("Not an environment: "); for k,v in pairs(props) do print(k,v) end
	    end
	 else
	    print("Package '" .. pkgname .. "' not found")
	 end
	 os.exit()
      end
   elseif args.command == "repl" then
      local repl_mod = mod.import("repl", rosie_mod)
      if not args.verbose then greeting(); end
      repl_mod.repl(en)
      os.exit()
   else
      -- match, trace, grep
      for _,fn in ipairs(args.filename) do
	 cli_match.process_pattern_against_file(rosie, en, args, compiled_pattern, fn)
      end
   end -- if command is list or repl or other
end -- function run

local args = parser:parse()
run(args)
