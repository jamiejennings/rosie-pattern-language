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
require("repl")
require("list")

CL_ENGINE, msg = lapi.new_engine({name="command line engine"})
if (not CL_ENGINE) then error("Internal error: could not obtain new engine: " .. msg); end

local function greeting()
	io.stderr:write("This is Rosie v" .. ROSIE_VERSION .. "\n")
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
end

function process_pattern_against_file(args, infilename)
	-- (3) Set up the input, output and error parameters
	if infilename=="-" then infilename = ""; end	    -- stdin
	outfilename = ""				    -- stdout
	errfilename = "/dev/null"
	if args.all then errfilename = ""; end			-- stderr

	-- (4) Set up what kind of encoding we want done on the output
	encode = args.encode -- default is color
	success, msg = lapi.configure_engine(CL_ENGINE, {encode=encode})
	if not success then io.write("Engine configuration error: ", msg, "\n"); os.exit(-1); end

	-- (5) Iterate through the lines in the input file
	local match_function = lapi.match_file
	if eval then match_function = lapi.eval_file; end
	local cin, cout, cerr = match_function(CL_ENGINE, infilename, outfilename, errfilename, args.wholefile)--OPTION["-wholefile"])
	if not cin then io.write(cout, "\n"); os.exit(-1); end -- cout is error message in this case

	-- (6) Print summary
	if args.verbose then
		local fmt = "Rosie: %d input items processed (%d matches, %d items unmatched)\n"
		io.stderr:write(string.format(fmt, cin, cout, cerr))
	end
end

function run(args)
	if args.command == "info" then
		print_rosie_info()
		os.exit()
	end

	if args.verbose then greeting(); end

	setup_engine(args);

	if args.command == "patterns" then
		if not args.verbose then greeting(); end
		local env = lapi.get_environment(CL_ENGINE)
		common.print_env(env, args.filter)
		os.exit()
	end

	if args.command == "repl" then
		if not args.verbose then greeting(); end
		repl(CL_ENGINE)
		os.exit()
	end

	for _,fn in ipairs(args.filename) do
		if (args.verbose) or (#args.filename > 1) then
			print("\n" .. fn .. ":")
		end
		process_pattern_against_file(args, fn)
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
	:default("")
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
