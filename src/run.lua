---- -*- Mode: Lua; -*-
----
---- run.lua
----
---- © Copyright IBM Corporation 2016.
---- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
---- AUTHOR: Jamie A. Jennings

-- This script is run in the lua interpreter by a shell script.  The script supplies the first two
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

-- Start the Rosie Pattern Engine

rosie = false; -- MUST BE GLOBAL FOR REPL TO USE IT

local msg
rosie, msg = loadfile(ROSIE_HOME .. "/src/init.lua") -- FIXME
if not rosie then
   io.stderr:write("Rosie CLI warning: compiled Rosie files not available, loading from source\n")
   rosie = dofile(ROSIE_HOME.."/src/core/init.lua")
else
   local rosie, msg = pcall(thunk)
   if not rosie then
      io.stderr:write("Rosie CLI warning: error loading compiled Rosie files, will load from source \n")
      io.stderr:write(msg, "\n")
      rosie = dofile(ROSIE_HOME.."/src/core/init.lua")
   end
end

local argparse = require "argparse"
local common = require "common"
local lapi = require "lapi"
local json = require "cjson"
local list = require("list")
--local repl_mod = require("repl")

CL_ENGINE = rosie.engine.new("command line engine")
if (not CL_ENGINE) then error("Internal error: could not obtain new engine: " .. msg); end

local function print_rosie_info()
   local function printf(fmt, ...)
      print(string.format(fmt, ...))
   end
   local fmt = "%15s = %s"
   for _,info in ipairs(ROSIE_INFO) do printf(fmt, info.name, info.value); end
end

local function greeting()
	io.write("This is Rosie " .. ROSIE_VERSION .. "\n")
end

-- global
VERBOSE = false;

local function set_encoder(name)
   local encode_fcn = rosie.encoders[name]
   if type(encode_fcn)~="function" then
      local msg = "Invalid output encoder: " .. tostring(name)
      if ROSIE_DEV then error(msg)
      else io.write(msg, "\n"); os.exit(-1); end
   end
   CL_ENGINE:output(encode_fcn)
end

function setup_engine(args)
   -- (1a) Load the manifest
   if args.manifest then
      if args.verbose then
	 VERBOSE = true;
	 io.stdout:write("Compiling files listed in manifest ", args.manifest, "\n")
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
   -- if args.pattern then
   --    local success, msg
   --    if args.grep then
   -- 	 success, msg = lapi.set_match_exp_grep_TEMPORARY(CL_ENGINE, args.pattern, "json")
   --    else
   -- 	 success, msg = lapi.configure_engine(CL_ENGINE, {expression=args.pattern, encode="json"})
   --    end
   --    if not success then
   -- 	 io.write(msg, "\n")
   -- 	 os.exit(-1);
   --    end
   -- end
end

infilename, outfilename, errfilename = nil, nil, nil

function process_pattern_against_file(args, infilename)
	-- (3) Set up the input, output and error parameters
	if infilename=="-" then infilename = ""; end	    -- stdin
	outfilename = ""				    -- stdout
	errfilename = "/dev/null"
	if args.all then errfilename = ""; end	            -- stderr

	-- (4) Set up what kind of encoding we want done on the output
	set_encoder(args.encode)

	-- (5) Iterate through the lines in the input file
	local match_function
	if args.command=="match" then
	   match_function = rosie.file.match
	elseif args.command=="eval" then
	   match_function = rosie.file.eval
	elseif args.command=="grep" then
	   match_function = rosie.file.grep
	else
	   error("Internal error: unrecognized command: " .. tostring(args.command))
	end
	local cin, cout, cerr = match_function(CL_ENGINE, args.pattern, infilename, outfilename, errfilename, args.wholefile)
	if not cin then io.write(cout, "\n"); os.exit(-1); end -- cout is error message in this case

	-- (6) Print summary
	if args.verbose then
		local fmt = "Rosie: %d input items processed (%d matches, %d items unmatched)\n"
		io.stderr:write(string.format(fmt, cin, cout, cerr))
	end
end

function setup_and_run_tests(args)
   -- first, set up the rosie CLI engine and automatically load the file being tested (after
   -- loading all the other stuff per the other command line args and defaults)
   if not args.rpls then
      args.rpls = { args.filename }
   else
      table.insert(args.rpls, args.filename)
   end
   setup_engine(args);
      
   local function startswith(str,sub)
      return string.sub(str,1,string.len(sub))==sub
   end
   -- from http://www.inf.puc-rio.br/~roberto/lpeg/lpeg.html
   local function split(s, sep)
      sep = lpeg.P(sep)
      local elem = lpeg.C((1 - sep)^0)
      local p = lpeg.Ct(elem * (sep * elem)^0)
      return lpeg.match(p, s)
   end
   local function find_test_lines(str)
      local num = 0
      local lines = {}
      for _,line in pairs(split(str, "\n")) do
	 if startswith(line,'-- test') then
	    table.insert(lines, line)
	    num = num + 1
	 end
      end
      return num, lines
   end
   local f = io.open(args.filename, 'r')
   local num_patterns, test_lines = find_test_lines(f:read('*a'))
   f:close()
   if num_patterns > 0 then
      local function test_accepts_exp(exp, q)
	 local res, pos = CL_ENGINE:match(exp, q)
	 if pos ~= 0 then return false end
	 return true
      end
      local function test_rejects_exp(exp, q)
	 local res, pos = CL_ENGINE:match(exp, q)
	 if pos == 0 then return false end
	 return true
      end
      local test_funcs = {test_rejects_exp=test_rejects_exp,test_accepts_exp=test_accepts_exp}
      local test_patterns =
	 [==[
	    testKeyword = "accepts" / "rejects"
	    test_line = "-- test" identifier testKeyword quoted_string (ignore "," ignore quoted_string)*
         ]==]

      lapi.load_file(CL_ENGINE, "$sys/src/rpl-core.rpl")
      lapi.load_string(CL_ENGINE, test_patterns)
      set_encoder(false)
      local failures = 0
      local exp = "test_line"
      for _,p in pairs(test_lines) do
	 local m, left = CL_ENGINE:match(exp, p)
	 -- FIXME: need to test for failure to match
	 local name = m.test_line.subs[1].identifier.text
	 local testtype = m.test_line.subs[2].testKeyword.text
	 local testfunc = test_funcs["test_" .. testtype .. "_exp"]
	 local literals = 3 -- literals will start at subs offset 3
	 -- if we get here we have at least one per test_line expression rule
	 while literals <= #m.test_line.subs do
	    local teststr = m.test_line.subs[literals].literal.text
	    if not testfunc(name, teststr) then
	       print("FAIL: " .. name .. " did not " .. testtype:sub(1,-2) .. " " .. teststr)
	       failures = failures + 1
	    end
	    literals = literals + 1
	 end
      end
      if failures == 0 then
	 print("All tests passed")
      else
	 os.exit(-1)
      end
   else
      print("No tests found")
   end
   os.exit()
end


function run(args)
   if args.command == "info" then
      greeting()
      print_rosie_info()
      os.exit()
   end

   if args.verbose then greeting(); end

   if args.command == "test" then
      -- lightweight pattern test framework does a custom setup
      setup_and_run_tests(args);
   end
   
   setup_engine(args);

   if args.command == "patterns" then
      if not args.verbose then greeting(); end
      local env = CL_ENGINE:lookup()
      common.print_env(env, args.filter)
      os.exit()
   end

   if args.command == "repl" then
      repl_mod = load_module("repl")
      if not args.verbose then greeting(); end
      repl_mod.repl(CL_ENGINE)
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
local parser = argparse("rosie", "Rosie Pattern Language " .. ROSIE_VERSION)
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
parser:option("-m --manifest", "Load a manifest file (single dash '-' for none)")
	:default("$sys/MANIFEST")
	:args(1)
parser:option("-f --file", "Load an RPL file")
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
-- eval command
local eval = parser:command("eval")
	:description("Run RPL evaluator (generates trace of every match)")
-- grep command
local grep = parser:command("grep")
	:description("Run RPL match in the style of Unix grep (match anywhere in a line)")

for _, cmd in ipairs{match, eval, grep} do
   -- match/eval/grep flags (true/false)
   cmd:flag("-s --wholefile", "Read input file as single string")
       :default(false)
       :action("store_true")
   cmd:flag("-a --all", "Output non-matching lines to stderr")
      :default(false)
      :action("store_true")

   -- match/eval/grep arguments (required options)
   cmd:argument("pattern", "RPL pattern")
   cmd:argument("filename", "Input filename")
      :args("*")
      :default("-") -- in case no filenames are passed, default to stdin
   -- match/eval/grep options (takes an argument)
   cmd:option("-o --encode", "Output format")
      :convert(function(a)
		  -- validation of argument, will fail if not in choices array
		  local choices={"color","nocolor","fulltext","json"}
		  for j=1,#choices do
		     if a == choices[j] then
			return a
		     end
		  end
		  return nil
	       end)
      :default("color")
      :args(1) -- consume argument after option
end

-- test command
local test = parser:command("test")
test:argument("filename", "RPL filename")


-- in order to catch dev mode for "make test"
if (not arg[1]) then
	print(parser:get_help())
else
	-- parse command-line
	local args = parser:parse()
	run(args)
end
