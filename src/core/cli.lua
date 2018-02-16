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

ROSIE_VERSION = rosie.attributes.ROSIE_VERSION
rosie.set_attribute("ROSIE_COMMAND", rosie_command, "CLI")

common = rosie.import("common")
ui = assert(rosie.import("ui"), "failed to open ui package")
argparser = assert(rosie.import("cli-parser"), "failed to load cli parser package")
cli_match = assert(rosie.import("cli-match"), "failed to open cli match package")
cli_common = assert(rosie.import("cli-common"), "failed to open cli common package")
engine_module = assert(rosie.import("engine_module"), "failed to open engine_module")

parser = argparser.create(rosie)

local function print_rosie_config()
   local function printf(fmt, ...)
      print(string.format(fmt, ...))
   end
   local fmt1 = "%20s"
   local fmt = fmt1 .. " = %s (set by %s)"
   for _, attr in ipairs(rosie.attributes) do
      printf(fmt, attr.name, attr.value, attr.set_by); end
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
   return false
end
--    local config = rosie.attributes
--    local libpath = config.ROSIE_LIBPATH
--    local dirs = common.parse_pathlist(libpath or "")
--    local msg = {"The RPL 'import' statement will search these directories in order (this is the libpath):"}
--    for _, dir in ipairs(dirs) do table.insert(msg, "\t" .. dir); end
--    return table.concat(msg, '\n')


local function run(args)
   en = assert(cli_engine)			    -- created by rosie.c

   if args.verbose then ROSIE_VERBOSE = true; end

   if (not args.norcfile) then
      engine_module.execute_rcfile(en,
				   args.rcfile,
				   rosie.engine.new,
				   (args.rcfile==rosie.config.default_rcfile))
      --rosie.set_configuration("ROSIE_RCFILE", args.rcfile)
   end

   if args.libpath then
      en:set_libpath(args.libpath)
      rosie.set_libpath(args.libpath, "cli")
   end

   if args.colors then
      en:set_encoder_parm("colors", args.colors)
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
      if text then parser:epilog(text); end
      print(parser:get_help())
      return
   end
   
   if args.verbose then greeting(); end

   -- FUTURE:
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
      local cl_engine = assert(cli_engine) --create_cl_engine()
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
      local representation = ast.tostring(aa, true)
      if ast.sequence.is(aa) then
	 print(string.format("Expands to:     {%s}", representation))
      else
	 print(string.format("Expands to:     %s", representation))
      end
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
