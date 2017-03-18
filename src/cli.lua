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

-- Start the Rosie Pattern Engine

rosie = false;				    -- must be GLOBAL so repl can use it
local thunk, msg = loadfile(ROSIE_HOME .. "/lib/init.luac", "b")
if not thunk then
   io.stderr:write("Rosie CLI warning: compiled Rosie files not available, loading from source\n")
   rosie = dofile(ROSIE_HOME.."/src/core/init.lua")
else
   rosie = thunk()
   if not rosie then
      msg = arg[0] .. ": corrupt compiled lua file lib/init.luac\n"
      if ROSIE_DEV then error(msg)
      else io.write(msg, "\n"); os.exit(-1); end
   end
end
assert(type(rosie)=="table", "Return value from init was not the rosie module (a table)")

local engine=require "engine"			    -- for debugging
local argparse = require "argparse"
local common = require "common"
local json = require "cjson"
local list = require("list")

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

local function set_encoder(name)
   local encode_fcn = rosie.encoders[name]
   if type(encode_fcn)~="function" then
      local msg = "Invalid output encoder: " .. tostring(name)
      if ROSIE_DEV then error(msg)
      else io.write(msg, "\n"); os.exit(-1); end
   end
   CL_ENGINE:output(encode_fcn)
end

local function load_string(en, input)
   local ok, results, messages = pcall(en.load, en, input)
   if not ok then
      if ROSIE_DEV then error(results)		    -- error(messages:concat("\n"));
      else io.write("Cannot load rpl: \n", results); os.exit(-1); end
   end
   return results, messages
end

local function setup_engine(args)
   -- (1a) Load the manifest
   if args.manifest then
      if args.verbose then
	 io.stdout:write("Compiling files listed in manifest ", args.manifest, "\n")
      end
      local success, messages = pcall(rosie.file.load, CL_ENGINE, args.manifest, "manifest")
      if not success then
	 io.stdout:write(table.concat(messages, "\n"), "\n")
	 os.exit(-4)
      else
	 if args.verbose then
	    for _, msg in ipairs(messages) do io.stdout:write(msg, "\n"); end
	 end
      end
   end -- load manifest

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
      local flavor = (args.command=="grep") and "search" or "match"
      local ok, msgs
      ok, compiled_pattern, msgs = pcall(CL_ENGINE.compile, CL_ENGINE, args.pattern, flavor)
      if not ok then
	 io.stdout:write(compiled_pattern, "\n")
	 os.exit(-4)
      elseif not compiled_pattern then
	 io.stdout:write(table.concat(msgs, '\n'), '\n')
	 os.exit(-4)
      end
   end
end

infilename, outfilename, errfilename = nil, nil, nil

local function process_pattern_against_file(args, infilename)
   assert(compiled_pattern, "Rosie: missing pattern?")
   assert(engine.rplx.is(compiled_pattern), "Rosie: compiled pattern not rplx?")

	-- (3) Set up the input, output and error parameters
	if infilename=="-" then infilename = ""; end	    -- stdin
	outfilename = ""				    -- stdout
	errfilename = "/dev/null"
	if args.all then errfilename = ""; end	            -- stderr

	-- (4) Set up what kind of encoding we want done on the output
	set_encoder(args.encode)

	if (args.verbose) or (#args.filename > 1) then
	   print("\n" .. infilename .. ":")		    -- print name of file before its output
	end

	-- (5) Iterate through the lines in the input file
	local match_function = (args.command=="trace") and rosie.file.tracematch or rosie.file.match 

	local ok, cin, cout, cerr =
	   pcall(match_function, CL_ENGINE, compiled_pattern, nil, infilename, outfilename, errfilename, args.wholefile)
	if not ok then io.write(cin, "\n"); os.exit(-1); end -- cout is error message in this case

	-- (6) Print summary
	if args.verbose then
		local fmt = "Rosie: %d input items processed (%d matches, %d items unmatched)\n"
		io.stderr:write(string.format(fmt, cin, cout, cerr))
	end
end

local function setup_and_run_tests(args)
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

      rosie.file.load(CL_ENGINE, "$sys/rpl/rpl-1.0.rpl", "rpl")
      load_string(CL_ENGINE, test_patterns)
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
	    teststr = common.unescape_string(teststr) -- allow, e.g. \" inside the test string
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


local function run(args)
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
      process_pattern_against_file(args, fn)
   end
end -- function run

----------------------------------------------------------------------------------------
-- Parser for command line args
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
-- target variable for commands
parser:command_target("command")
-- info command
local cmd_info = parser:command("info")
	:description("Print rosie installation information")
-- patterns command
local cmd_patterns = parser:command("patterns")
	:description("List installed patterns")
cmd_patterns:argument("filter")
	:description("Filter pattern names that have substring 'filter'")
	:args("?")
-- repl command
local cmd_repl = parser:command("repl")
	:description("Run rosie in interactive mode")
-- match command
local cmd_match = parser:command("match")
	:description("Run RPL match")
-- trace command
local cmd_trace = parser:command("trace")
	:description("Match while tracing all steps (generates MUCH output)")
-- grep command
local cmd_grep = parser:command("grep")
	:description("Run RPL match in the style of Unix grep (match anywhere in a line)")

local output_choices={"color","nocolor","fulltext","json", "none"}
local output_choices_string = output_choices[1]
for i=2,#output_choices do
   output_choices_string = output_choices_string .. ", " .. output_choices[i]
end

for _, cmd in ipairs{cmd_match, cmd_trace, cmd_grep} do
   -- match/trace/grep flags (true/false)
   cmd:flag("-s --wholefile", "Read input file as single string")
       :default(false)
       :action("store_true")
   cmd:flag("-a --all", "Output non-matching lines to stderr")
      :default(false)
      :action("store_true")

   -- match/trace/grep arguments (required options)
   cmd:argument("pattern", "RPL pattern")
   cmd:argument("filename", "Input filename")
      :args("+")
      :default("-")			      -- in case no filenames are passed, default to stdin
      :defmode("arg")			      -- needed to make the default work
   -- match/trace/grep options (takes an argument)
   cmd:option("-o --encode", "Output format, one of " .. output_choices_string)
      :convert(function(a)
		  -- validation of argument, will fail if not in choices array
		  for j=1,#output_choices do
		     if a == output_choices[j] then
			return a
		     end
		  end
		  return nil
	       end)
      :default("color")
      :args(1) -- consume argument after option
end

-- test command
local cmd_test = parser:command("test")
cmd_test:argument("filename", "RPL filename")


-- Check arg[1] in order to catch dev mode for "make test"
if (not arg[1]) then
	print(parser:get_help())
else
	-- parse command-line
	local args = parser:parse()
	run(args)
end
