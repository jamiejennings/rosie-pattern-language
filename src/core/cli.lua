---- -*- Mode: Lua; -*-
----
---- cli.lua    A Rosie CLI made to be launched from librosie:rosie_luacli()
----
---- © Copyright IBM Corporation 2016, 2017, 2018.
---- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
---- AUTHOR: Jamie A. Jennings

rosie_command = arg[0]

ROSIE_HOME = rosie.env.ROSIE_HOME

if not ROSIE_HOME then
	io.stderr:write("Installation error: Lua variable ROSIE_HOME is not defined\n")
	io.stderr:flush()
	return ERROR_INTERNAL
end

package.path = ROSIE_HOME .. "/lib/?.luac"

ROSIE_VERSION = rosie.config().ROSIE_VERSION
rosie.set_configuration("ROSIE_COMMAND", rosie_command)

common = rosie.import("common")
ui = assert(rosie.import("ui"), "failed to open ui package")
argparser = assert(rosie.import("cli-parser"), "failed to load cli parser package")
cli_match = assert(rosie.import("cli-match"), "failed to open cli match package")
cli_common = assert(rosie.import("cli-common"), "failed to open cli common package")

parser = argparser.create(rosie)

function create_cl_engine(args)
   local cl_engine = rosie.engine.new("command line engine")
   if (not cl_engine) then error("Internal error: could not obtain new engine: " .. msg); end
   cl_engine:set_libpath(rosie.config().ROSIE_LIBPATH)
   return cl_engine
end

local multi_sourced = {ROSIE_LIBPATH = "ROSIE_LIBPATH_SOURCE"}

local function print_rosie_config()
   local function printf(fmt, ...)
      print(string.format(fmt, ...))
   end
   local fmt1 = "%20s"
   local fmt = fmt1 .. " = %s"
   local config = rosie.config()
   local function print_if_source(sourcetype)
      local any = false
      for name, sourcename in pairs(multi_sourced) do
	 if config[sourcename] == sourcetype then
	    if not any then
	       print()
	       any = true
	    end
	    printf(fmt, name, config[name])
	 end
      end -- for
      if not any then print("  None"); end
   end
   io.write("Configured from environment variable: ")
   print_if_source("env")
   print()
   io.write("Configured on command line: ")
   print_if_source("cli")
   print()
   print("Internal configuration:")
   for _, info in ipairs(config) do printf(fmt, info.name, info.value); end
   print()
   io.write("Build log: ")
   local buildlogfile = ROSIE_HOME .. "/build.log"
   local log = io.open(buildlogfile, "r")
   if log then
      io.write(buildlogfile, "\n")
      log:close()
   else
      io.write("Not found\n")
   end
end

local function greeting()
   io.write("Rosie " .. ROSIE_VERSION .. "\n")
end

local function make_help_epilog(args)
   local config = rosie.config()
   local libpath = config.ROSIE_LIBPATH
   local dirs = common.parse_pathlist(libpath or "")
   local msg = {"The RPL 'import' statement will search these directories in order (this is the libpath):"}
   for _, dir in ipairs(dirs) do table.insert(msg, "\t" .. dir); end
   return table.concat(msg, '\n')
end

local function run(args)
   en = assert(cli_engine)

   if args.verbose then ROSIE_VERBOSE = true; end

   if args.libpath then
      en:set_libpath(args.libpath)
      rosie.set_libpath(args.libpath, "cli")
   end

   if not args.command then
      print("Usage: rosie command [options] pattern file [...]")
      return cli_common.ERROR_USAGE
   end

   if args.command=="version" then
      io.write(ROSIE_VERSION, "\n")
      return
   end

   if args.command=="config" then
      print_rosie_config()
      return
   end
   
   if args.command=="help" then
      local text = make_help_epilog(args)
      print("***", text)
      if text then parser:epilog(text); end
      print(parser:get_help())
      return
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
      local cl_engine = create_cl_engine()
      local a = cl_engine.compiler.parse_expression(common.source.new{text=args.expression}, errs)
      if not a then
	 for _,e in ipairs(errs) do print(violation.tostring(e)) end
	 return cli_common.ERROR_RESULT
      end
      print("Parses as: ", ast.tostring(a, true))
      a = ast.ambient_cook_exp(a)
      print("At top level: ", ast.tostring(a, true))
      local aa = expand.expression(a, cl_engine.env, errs)
      if not aa then
	 for _,e in ipairs(errs) do print(violation.tostring(e)) end
	 return cli_common.ERROR_RESULT
      end
      print("Expands to: ", ast.tostring(aa, true))
      return
   end
   
   if args.command == "test" then
      -- lightweight pattern test framework does a custom setup:
      -- for each file being tested
      --     get a fresh engine and load any rpl files or rpl strings
      --     load the file being tested
      --     call the test procedure
      cli_test = assert(rosie.import("cli-test-command"), "failed to open cli test package")
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
	 print("\nTOTALS:")
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
      if ((total_files - total_compiled) > 0) or (total_failures > 0) then
	 return cli_common.ERROR_RESULT
      else
	 return
      end
   end
   
   local compiled_pattern = cli_common.setup_engine(en, args);
   if type(compiled_pattern)=="number" then -- return the error
      return compiled_pattern
   end

   if args.command == "list" then
      if not args.verbose then greeting(); end
      local props_table, msg = ui.to_property_table(en.env, args.filter)
      if props_table then
	 ui.print_props(props_table)
	 return
      else
	 print(msg)
	 return cli_common.ERROR_RESULT
      end
   elseif args.command == "repl" then
      local repl_mod = assert(rosie.import("repl"), "failed to open the repl package")
      if not args.verbose then greeting(); end
      repl_mod.repl(en)
      return
   else
      -- match, trace, grep
      for _,fn in ipairs(args.filename) do
	 cli_match.process_pattern_against_file(rosie, en, args, compiled_pattern, fn)
      end
   end -- if command is list or repl or other
end -- function run

local args = parser:parse(arg)
return run(args)
