---- -*- Mode: Lua; -*-                                                                           
----
---- run.lua
----
---- © Copyright IBM Corporation 2016.
---- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
---- AUTHOR: Jamie A. Jennings


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
   dofile(ROSIE_HOME.."/src/bootstrap.lua")
else
   local ok, msg = pcall(thunk)
   if not ok then
      io.stderr:write("Rosie CLI warning: error loading compiled Rosie files, will load from source \n")
      io.stderr:write(msg, "\n")
      dofile(ROSIE_HOME.."/src/bootstrap.lua")
   end
end

local common = require "common"
local lapi = require "lapi"
local json = require "cjson"
require("repl")
require "list"

CL_ENGINE, msg = lapi.new_engine("command line engine")
if (not CL_ENGINE) then error("Internal error: could not obtain new engine: " .. msg); end

local function greeting()
   io.stderr:write("This is Rosie v" .. ROSIE_VERSION .. "\n")
end

local options_without_args = {"-help", "-patterns", "-verbose", "-json", "-nocolor", "-all",
			      "-repl", "-grep", "-eval" }
local options_with_args = {"-manifest", "-f", "-e" }

local valid_options = append(options_without_args, options_with_args)

local function option_takes_arg(optname)
   return member(optname, options_with_args)
end

local function valid_option_is(opt)
   for i,v in ipairs(valid_options) do
      if v==opt then return i; end
   end
   return false
end

local usage_message = "Rosie usage: "..(SCRIPTNAME or "<this script>").." <options> <pattern> <filename>*\n"
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

function process_command_line_options()
   OPTION = {}				    -- GLOBAL array indexed by option name
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

   opt_manifest = OPTION["-manifest"] or "MANIFEST"
   if opt_manifest==true then
      io.write("Rosie: the manifest command line option requires a filename or - \n")
      io.write(usage_message, "\n")
      os.exit(-1)
   elseif opt_manifest=="-" then
      opt_manifest=nil
   end

end

function help()
   greeting()
   print("The Rosie install directory is: " .. ROSIE_HOME)
   print("Rosie help:")
   print(usage_message)
   print()
   print("  -help           prints this message")
   print("  -verbose        output warnings and other informational messages")
   print("  -repl           start Rosie in the interactive mode (read-eval-print loop)")
   print("  -patterns       read manifest file, compile patterns, show pattern list (but process no input)")
   print("  -json           produce output in JSON instead of color text")
   print("                  (the default is terminal window output, with recognized items shown in color")
   print("  -nocolor        output the matching text only (no escape sequences for color)")
   print("  -all            output everything: matches to stdout and non-matching lines to stderr")
   print("  -eval           output a detailed \"trace\" evaluation of how the pattern processed the input;")
   print("                  this feature generates LOTS of output, so best to use it on ONE LINE OF INPUT;")
   print("  -grep           emulate grep, but with RPL, by searching for all occurrences of <pattern> in the input")
   print("  -manifest <fn>  load the manifest file <fn> instead of MANIFEST from the Rosie install directory")
   print("  -f <fn>         RPL file to load, after manifest (if any) is loaded")
   print("  -e <rpl>        RPL statements to load, after manifest and RPL file (if any) are loaded")
   print()
   print("  <pattern>       RPL expression, which may be the name of a defined pattern, against which each line will be matched")
   print("  <fn>+           one or more file names of text input, the last of which may be a dash \"-\" to read from standard input")
   print()
   print("Notes: ")
   print("(1) lines from the input file for which the pattern does NOT match are written to stderr so they can be redirected, e.g. to /dev/null")
   print("(2) the -eval option currently does not work with the -grep option")
   print("(3) to load no manifest file at all, supply a single dash as the filename argument: -manifest -")
   print()
end

function setup_engine()
   if OPTION["-grep"] and OPTION["-eval"] then
      print("Error: currently, the -grep option and the -eval option are incompatible.  Use one or the other.")
      os.exit(-1)
   end
   local eval = OPTION["-eval"]
   -- (1a) Load the manifest
   if opt_manifest then
      local success, msg = lapi.load_manifest(CL_ENGINE, opt_manifest)
      if not success then
	 io.stdout:write(msg, "\n")
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
	 success, msg = lapi.configure_engine(CL_ENGINE, {expression=opt_pattern, encoder="json"})
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
   encoder = "color"
   if OPTION["-json"] then encoder = "json"
   elseif OPTION["-nocolor"] then encoder = "text"; end
   success, msg = lapi.configure_engine(CL_ENGINE, {encoder=encoder})
   if not success then io.write(msg, "\n"); os.exit(-1); end

   -- (5) Iterate through the lines in the input file
   local match_function = lapi.match_file
   if eval then match_function = lapi.eval_file; end
   local cin, cout, cerr = match_function(CL_ENGINE, infilename, outfilename, errfilename)
   if not cin then io.write(cout, "\n"); os.exit(-1); end -- cout is error message in this case

   -- (6) Print summary
   if not QUIET then
      local fmt = "Rosie: %d input items processed (%d matches, %d items unmatched)\n"
      io.stderr:write(string.format(fmt, cin, cout, cerr))
   end
end

----------------------------------------------------------------------------------------
-- Do stuff
----------------------------------------------------------------------------------------

if (not arg[1]) then
   -- no command line options were supplied
   greeting()
   print(usage_message)
   os.exit(-1)
end

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

if not QUIET then greeting(); end

setup_engine();

if OPTION["-patterns"] then
   if QUIET then greeting(); end
   local env = lapi.get_environment(CL_ENGINE)
   common.print_env(env)
   os.exit()
end

if not opt_pattern then print("Rosie CLI warning: missing pattern argument"); end

if opt_filenames then
   for _,fn in ipairs(opt_filenames) do
      if (not QUIET) or (#opt_filenames>1) then print("\n" .. fn .. ":"); end
      process_pattern_against_file(fn)
   end -- for each file
else
   print("Rosie CLI warning: missing filename arguments")
end

if OPTION["-repl"] then
   if QUIET then greeting(); end
   repl(CL_ENGINE)
end


