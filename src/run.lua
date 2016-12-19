---- -*- Mode: Lua; -*-
----
---- run.lua
----
---- © Copyright IBM Corporation 2016.
---- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
---- AUTHOR: Jamie A. Jennings

--function assert(x) return x; end


-- Notes:
--
-- This lua script must be called with the variable ROSIE_HOME set to be the full path of the
-- Rosie installation (not a relative path such as one starting with . or ..), and SCRIPTNAME set
-- to arg[0] of the shell script that invoked this code.
--
-- "-D" is an 'undocumented' command line switch which, when it appears as the first command line
-- argument to the Rosie run script, will launch Rosie in development mode.  The code below does
-- not need to process that switch.

if not ROSIE_HOME then
	io.stderr:write("Installation error: Lua variable ROSIE_HOME is not defined\n")
	os.exit(-2)
end
-- if not SCRIPTNAME then
--    io.stderr:write("Installation error: Lua variable SCRIPTNAME is not defined\n")
--    os.exit(-2)
-- end

-- This will be set by bootstrap.lua to be the value of ROSIE_HOME provided by the start script
-- (as opposed to the env variable $ROSIE_HOME).
SCRIPT_ROSIE_HOME=false;

-- Start the Rosie Pattern Engine

local thunk, msg = loadfile(ROSIE_HOME .. "/bin/bootstrap.luac")
if not thunk then
	io.stderr:write("Rosie CLI warning: compiled Rosie files not available, loading from source\n")
	dofile(ROSIE_HOME.."/src/core/bootstrap.lua")
else
	local ok, msg = pcall(thunk)
	if not ok then
		io.stderr:write("Rosie CLI warning: error loading compiled Rosie files, will load from source \n")
		io.stderr:write(msg, "\n")
		dofile(ROSIE_HOME.."/src/core/bootstrap.lua")
	end
end

local argparse = require "argparse"
local common = require "common"
local lapi = require "lapi"
local json = require "cjson"
local list = require("list")
require("repl")

CL_ENGINE, msg = lapi.new_engine({name="command line engine"})
if (not CL_ENGINE) then error("Internal error: could not obtain new engine: " .. msg); end

local function greeting()
   io.stderr:write("This is Rosie v" .. ROSIE_VERSION .. "\n")
end

local options_without_args = {"-help", "-patterns", "-verbose", "-all",
			      "-repl", "-grep", "-eval", "-wholefile", "-info"}
local options_with_args = {"-manifest", "-f", "-e", "-encode"}

local valid_options = list.append(options_without_args, options_with_args)

local help_messages =
   { ["-help"] = {"prints this message"},
     ["-info"] = {"prints information about the local rosie installation"},
     ["-verbose"] = {"output warnings and other informational messages"},
     ["-repl"] = {"start Rosie in the interactive mode (read-eval-print loop)"},
     ["-patterns"] = {"print list of available patterns"},
     ["-encode"] = {"encode output in <arg> format: color (default), nocolor,",
		    "fulltext, or json"},
     ["-wholefile"] = {"read the whole input file into memory as a single string,",
		       "instead of line by line"},
     ["-all"] = {"write matches to stdout and non-matching lines to stderr"},
     ["-eval"] = {"output a detailed \"trace\" evaluation of how the pattern",
		  "processed the input; this feature generates LOTS of output,",
		  "so best to use it on ONE LINE OF INPUT"},
     ["-grep"] = {"emulate grep (weakly), but with RPL, by searching for all",
		  "occurrences of <pattern> in the input"},
     ["-manifest"] = {"load the manifest file <arg> instead of MANIFEST from $sys",
		      "(the Rosie install directory); use a single dash '-' to",
		      "load no manifest file"},
     ["-f"] = {"load the RPL file <arg>, after manifest (if any) is loaded"},
     ["-e"] = {"compile the RPL statements in <arg>, after manifest and",
	       "RPL file (if any) are loaded"},
  }

local function option_takes_arg(optname)
   return list.member(optname, options_with_args)
end

local function valid_option_is(opt)
   for i,v in ipairs(valid_options) do
      if v==opt then return i; end
   end
   return false
end

local usage_message = "Usage: "..(SCRIPTNAME or "<this script>").." <options> <pattern> <filename>*\n"
usage_message = usage_message .. "Valid <options> are: " .. table.concat(valid_options, " ")

----------------------------------------------------------------------------------------
-- Option processing
----------------------------------------------------------------------------------------

function invalid_option(j)
   greeting()
   io.write("Rosie: invalid command line option ", arg[j], "\n")
   if arg[j]=="-" then
      io.write("\tHint: A single dash can replace the manifest filename to prevent a manifest from loading, or\n")
      io.write("\tit can be the last (or only) input file name, which causes input to be read from the stdin.\n")
   end
   io.write(usage_message, "\n")
   os.exit(-1)
end

----------------------------------------------------------------------------------------
-- Globals set up by process_command_line_options()
--
QUIET = true;
OPTION = {}				    -- indexed by option name
opt_filenames = nil
opt_pattern = nil
opt_manifest = nil
opt_eval = nil
infilename, outfilename, errfilename = nil, nil, nil
----------------------------------------------------------------------------------------

function process_command_line_options()
   OPTION = {}
   local last_option = 0		    -- index of last command line option found
   local value
   local i=1
   while arg[i] do
      local v = arg[i]
      if valid_option_is(v) then
	 if option_takes_arg(v) then
	    value = arg[i+1]
	    last_option = i+1;
	 else
	    value = true
	    last_option = i;
	 end
	 OPTION[v] = value
      else
	 break;
      end
      i = last_option+1;
   end -- while

   -- i is now the first non-option argument, which should be a pattern expression
   if arg[i] then
      if arg[i]:sub(1,1)=="-" then invalid_option(i); end
      opt_pattern = arg[i]
      i = i+1
   end

   -- any remaining args are filenames, only the last of which can be "-"
   local firstfile = i
   while arg[i] do
      local v = arg[i]
      if (v=="-") and (arg[i+1]) then invalid_option(i); end
      i = i+1
   end

   if firstfile==i then
      -- no files on command line
      opt_filenames = nil
   else
      opt_filenames = {table.unpack(arg, firstfile)}
   end

   opt_manifest = OPTION["-manifest"] or "$sys/MANIFEST"
   if opt_manifest==true then
      io.write("Rosie: the manifest command line option requires a filename or - \n")
      io.write(usage_message, "\n")
      os.exit(-1)
   elseif opt_manifest=="-" then
      opt_manifest=nil
   end

end

function print_rosie_info()
	-- Find the value of the environment variable "ROSIE_HOME", if it is defined
	if not ((type(os)=="table") and (type(os.getenv)=="function")) then
		error("Internal error: os functions unavailable; cannot use getenv to find ROSIE_HOME")
	end
	local ok, env_ROSIE_HOME = pcall(os.getenv, "ROSIE_HOME")
	if not ok then
		error("Internal error: call to os.getenv failed")
	end

	local rosie_home_message = ((SCRIPT_ROSIE_HOME and " (from environment variable $ROSIE_HOME)") or
			" (provided by the program that initialized Rosie)")
	print("Local installation information:")
	print("  ROSIE_HOME = " .. ROSIE_HOME)
	print("  ROSIE_VERSION = " .. ROSIE_VERSION)
	print("  HOSTNAME = " .. (os.getenv("HOSTNAME") or ""))
	print("  HOSTTYPE = " .. (os.getenv("HOSTTYPE") or ""))
	print("  OSTYPE = " .. (os.getenv("OSTYPE") or ""))
	print("Current invocation: ")
	print("  current working directory = " .. (os.getenv("CWD") or ""))
	print("  invocation command = " .. (SCRIPTNAME or ""))
	print("  script value of Rosie home = " .. (os.getenv("ROSIE_SCRIPT_HOME") or "(not set???)"))
	local env_var_msg = "  environment variable $ROSIE_HOME "
	if env_ROSIE_HOME then
		if env_ROSIE_HOME=="" then
			env_var_msg = env_var_msg .. "is set to the empty string"
		else
			env_var_msg = env_var_msg .. "= " .. tostring(env_ROSIE_HOME)
		end
	else
		env_var_msg = env_var_msg .. "is not set"
	end
	print(env_var_msg)
end

function setup_engine(args)
	-- (1a) Load the manifest
	if args.manifest then
		if args.verbose then
			io.stdout:write("Compiling files listed in manifest ", args.manifest, "\n")
		end
		local success, messages = lapi.load_manifest(CL_ENGINE, args.manifest)
		if not success then
			for _,msg in ipairs(messages) do
				if msg then
					io.stdout:write(msg, "\n")
				end
			end
			os.exit(-4)
		end
	end

	-- (1b) Load an rpl file
	if args.rpls then
		for _,file in pairs(args.rpls) do
			if args.verbose then
				io.stdout:write("Compiling additional file ", file, "\n")
			end
			local success, msg = lapi.load_file(CL_ENGINE, file)
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
			local success, msg = lapi.load_string(CL_ENGINE, stm)
			if not success then
				io.stdout:write(msg, "\n")
				os.exit(-4)
			end
		end
	end

	-- (2) Compile the expression
	if args.pattern then
		local success, msg
		if args.grep then
			success, msg = lapi.set_match_exp_grep_TEMPORARY(CL_ENGINE, args.pattern, "json")
		else
			success, msg = lapi.configure_engine(CL_ENGINE, {expression=args.pattern, encode="json"})
		end
		if not success then
			io.write(msg, "\n")
			os.exit(-1);
		end
	end

function help()
   greeting()
   print("Help:")
   print(usage_message)
   print()
   local line
   for _, cmd in ipairs(valid_options) do
      if list.member(cmd, options_without_args) then
	 line = string.format("%-18s %s", cmd, help_messages[cmd][1])
      else
	 line = string.format("%-18s %s", cmd .. " <arg>", help_messages[cmd][1])
      end
      print(line)
      for i=2,#help_messages[cmd] do
	 print("                   " .. help_messages[cmd][i])
      end
   end -- for each cmd
   print()
   print("<pattern>            RPL expression, which may be the name of a defined pattern,")
   print("                     against which each line will be matched")
   print("<filename>+          one or more file names to process, the last of which may be")
   print("                     a dash \"-\" to read from standard input")
   print()
   print("Notes: ")
   print("(1) lines from the input file for which the pattern does NOT match are written")
   print("    to stderr so they can be redirected, e.g. to /dev/null")
   print("(2) the -eval option currently does not work with the -grep option")
   print()
end

function setup_engine()
   if OPTION["-grep"] and OPTION["-eval"] then
      print("Error: currently, the -grep option and the -eval option are incompatible.  Use one or the other.")
      os.exit(-1)
   end
   opt_eval = OPTION["-eval"]

   -- (1a) Load the manifest
   if opt_manifest then
      if not QUIET then io.stdout:write("Compiling files listed in manifest ", opt_manifest, "\n"); end
      local success, messages = lapi.load_manifest(CL_ENGINE, opt_manifest)
      if not success then
	 for _,msg in ipairs(messages) do if msg then io.stdout:write(msg, "\n"); end; end
	 os.exit(-4)
      end
   end

   -- (1b) Load an rpl file
   if OPTION["-f"] then
      if not QUIET then io.stdout:write("Compiling additional file ", OPTION["-f"], "\n"); end
      local success, msg = lapi.load_file(CL_ENGINE, OPTION["-f"])
      if not success then
	 io.stdout:write(msg, "\n")
	 os.exit(-4)
      end
   end

   -- (1c) Load an rpl string from the command line
   if OPTION["-e"] then
      if not QUIET then io.stdout:write(string.format("Compiling additional rpl code %q\n",  OPTION["-e"])); end
      local success, msg = lapi.load_string(CL_ENGINE, OPTION["-e"])
      if not success then
	 io.stdout:write(msg, "\n")
	 os.exit(-4)
      end
   end

   -- (2) Compile the expression
   if opt_pattern then
      local success, msg
      if OPTION["-grep"] then
	 success, msg = lapi.set_match_exp_grep_TEMPORARY(CL_ENGINE, opt_pattern, "json")
      else
	 success, msg = lapi.configure_engine(CL_ENGINE, {expression=opt_pattern, encode="json"})
      end
      if not success then io.write(msg, "\n"); os.exit(-1); end
   end
end

function process_pattern_against_file(infilename)
   -- (3) Set up the input, output and error parameters
   if infilename=="-" then infilename = ""; end	    -- stdin
   outfilename = ""				    -- stdout
   errfilename = "/dev/null"
   if OPTION["-all"] then errfilename = ""; end	    -- stderr

   -- (4) Set up what kind of encoding we want done on the output
   local encode = OPTION["-encode"] or "color"
   local success, msg = lapi.configure_engine(CL_ENGINE, {encode=encode})
   if not success then io.write("Engine configuration error: ", msg, "\n"); os.exit(-1); end

   -- (5) Iterate through the lines in the input file
   local match_function = lapi.match_file
   if opt_eval then match_function = lapi.eval_file; end
   local cin, cout, cerr = match_function(CL_ENGINE, infilename, outfilename, errfilename, OPTION["-wholefile"])
   if not cin then io.write(cout, "\n"); os.exit(-1); end -- cout is error message in this case

   -- (6) Print summary
   if not QUIET then
      local fmt = "Rosie: %d input items processed (%d matches, %d items unmatched)\n"
      io.stderr:write(string.format(fmt, cin, cout, cerr))
   end
end

function run()
   process_command_line_options()

   if OPTION["-verbose"] then
      QUIET = false;
   else
      QUIET = true;
   end

   if OPTION["-help"] then
      if #arg > 1 then print("Rosie CLI warning: ignoring extraneous command line arguments"); end
      help()
      os.exit()
   end

   if OPTION["-info"] then
      if #arg > 1 then print("Rosie CLI warning: ignoring extraneous command line arguments"); end
      print_rosie_info()
      os.exit()
   end

   if not QUIET then greeting(); end

   setup_engine();

   if OPTION["-patterns"] then
      if QUIET then greeting(); end
      local env = lapi.get_environment(CL_ENGINE)
      common.print_env(env)
      os.exit()
   end

   if OPTION["-repl"] then
      if QUIET then greeting(); end
      repl(CL_ENGINE)
   else
      if not opt_pattern then print("Rosie CLI warning: missing pattern argument"); end

      if opt_filenames then
	 for _,fn in ipairs(opt_filenames) do
	    if (not QUIET) or (#opt_filenames>1) then print("\n" .. fn .. ":"); end
	    process_pattern_against_file(fn)
	 end -- for each file
      else
	 print("Rosie CLI warning: missing filename arguments")
      end
   end
end -- function run

----------------------------------------------------------------------------------------
-- Do stuff
----------------------------------------------------------------------------------------

-- create Parser
local parser = argparse("rosie", "Rosie Pattern Language v" .. ROSIE_VERSION)
	:epilog("Additional information.")
-- global flags/options can go here
-- -h,--help is generated automatically
-- usage message is generated automatically
parser:flag("--version", "Print rosie version")
	:action(function(args,_,exceptions)
		greeting()
		os.exit()
	end)
parser:flag("-v --verbose", "Output additional messages")
	:default(false)
	:action("store_true")
parser:option("-m --manifest", "Load a manifest file")
	:default("$sys/MANIFEST")
	:args(1)
parser:option("-f --load", "Load an RPL file")
	:args(1)
	:count("*") -- allow multiple loads of a file
	:target("rpls") -- set name of variable index (args.rpls)
parser:option("-r --rpl", "Inline RPL statements")
	:args(1)
	:count("*") -- allow multiple RPL statements
	:target("statements") -- set name of variable index (args.statements)
--parser:flag("--asdf", "description")
--parser:option("--lkj", "description"):args(1)
-- target variable for commands
parser:command_target("command")
-- info command
local info = parser:command("info")
	:description("Print rosie installation information")
-- patterns command
local patterns = parser:command("patterns")
	:description("List installed patterns")
patterns:argument("filter")
	:description("Filter pattern names that have substring 'filter'")
	:args("?")
-- repl command
local repl = parser:command("repl")
	:description("Run rosie in interactive mode")
-- match command
local match = parser:command("match")
	:description("Run RPL match")
-- match flags (true/false)
match:flag("-s --wholefile", "Read input file as single string")
	:default(false)
	:action("store_true")
match:flag("-a --all", "Output non-matching lines to stderr")
	:default(false)
	:action("store_true")
-- mutually exclusive flags
match:mutex(
	match:flag("-e --eval", "Output detailed trace evaluation of pattern process.")
		:default(false)
		:action("store_true"),
	match:flag("-g --grep", "Weakly emulate grep using RPL syntax")
		:default(false)
		:action("store_true")
)
-- match options (takes an argument)
match:option("-o --encode", "Output format")
	:convert(function(a)
		-- validation of argument, will fail if not in choices array
		choices={"color","nocolor","fulltext","json"}
		for j=1,#choices do
			if a == choices[j] then
				return a
			end
		end
		return nil
		end)
	:default("color")
	:args(1) -- consume argument after option
-- match arguments (required options)
match:argument("pattern", "RPL pattern")
match:argument("filename", "Input filename")
	:args("*")
	:default("-") -- in case no filenames are passed, default to stdin
-- in order to catch dev mode for "make test"
if (not arg[1]) then
	print(parser:get_help())
else
	-- parse command-line
	local args = parser:parse()
	run(args)
end
