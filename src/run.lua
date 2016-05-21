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
dofile(ROSIE_HOME.."/src/bootstrap.lua")
--bootstrap()					    -- now done while loading

local common = require "common"
local lapi = require "lapi"
local json = require "cjson"
require("repl")

CL_ENGINE = lapi.new_engine("command line engine")

local function greeting()
   io.stderr:write("This is Rosie v" .. ROSIE_VERSION .. "\n")
end

local valid_options = {"-help", "-patterns", "-verbose", "-json", "-nocolor", "-all", "-repl", "-manifest", "-grep", "-eval"}

local function valid_option_is(opt)
   for i,v in ipairs(valid_options) do
      if v==opt then return i; end
   end
   return false
end

local usage_message = "Usage: "..(SCRIPTNAME or "<this script>").." <options> <pattern> <filename>\n"
usage_message = usage_message .. "Valid <options> are: " .. table.concat(valid_options, " ")

----------------------------------------------------------------------------------------
-- Option processing
----------------------------------------------------------------------------------------

function process_command_line_options()
   OPTION = {}				    -- GLOBAL array indexed by option name
   local last_option = 0		    -- index of last command line option found
   local skip_arg = false
   for i,v in ipairs(arg) do
      if skip_arg then
	 -- previous arg was an option that itself takes an argument, like "-manifest"
	 skip_arg = false;
      else
	 if valid_option_is(v) then
	    OPTION[v] = arg[i+1] or true;
	    last_option = i;
	    if v=="-manifest" then
	       last_option = i+1;	      -- only this option takes an arg
	       skip_arg = true;		      -- skip the next arg, which is the arg to this arg
	    end
	 elseif v:sub(1,1)=="-" and i~=#arg then    -- filename, which is always last, can be "-"
	    -- arg starts with a dash but is not a valid option
	    greeting()
	    io.write("Rosie: invalid command line option ", v, "\n")
	    io.write(usage_message, "\n")
	    os.exit(-1)
	 end
      end -- if manifest arg
   end -- for each command line arg

   opt_manifest = OPTION["-manifest"] or "MANIFEST"
   if opt_manifest==true then
      io.write("Rosie: the manifest command line option requires a filename or - \n")
      io.write(usage_message, "\n")
      os.exit(-1)
   elseif opt_manifest=="-" then
      opt_manifest=nil
   end

   if last_option==#arg-2 then
      opt_pattern = arg[#arg-1]
      opt_filename = arg[#arg]
   else
      opt_pattern = nil
      opt_filename = nil
   end
end

function help()
   greeting()
   print("The Rosie install directory is: " .. ROSIE_HOME)
   print("Rosie help:")
   print(usage_message)
   print()
   print("  -help           prints this message")
   print("  -verbose        output warnings and other informational messages (errors will still be shown)")
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
   print()
   print("  <pattern>       RPL expression, which may be the name of a defined pattern, against which each line will be matched")
   print("  <fn>            (filename) name of the file of text input, or a dash \"-\" to read from standard input")
   print()
   print("Notes: ")
   print("(1) lines from the input file for which the pattern does NOT match are written to stderr so they can be redirected, e.g. to /dev/null")
   print("(2) the -eval option currently does not work with the -grep option")
   print("(3) to load no manifest file at all, supply a single dash as the filename argument: -manifest -")
   print()
end

function process_pattern_against_file()
   if OPTION["-grep"] and OPTION["-eval"] then
      print("Error: currently, the -grep option and the -eval option are incompatible.  Use one or the other.")
      os.exit(-1)
   end
   local eval = OPTION["-eval"]
   -- (1) Load the manifest
   if opt_manifest then
      local success, msg = lapi.load_manifest(CL_ENGINE, opt_manifest)
      if not success then
	 io.stdout:write(msg, "\n")
	 os.exit(-4)
      end
   end
   -- (2) Compile the expression
   do 
      local success, msg
      if OPTION["-grep"] then
	 success, msg = lapi.set_match_exp_grep_TEMPORARY(CL_ENGINE, opt_pattern, "json")
      else
	 success, msg = lapi.configure(CL_ENGINE, {expression=opt_pattern, encoder="json"})
      end
      if not success then io.write(msg, "\n"); os.exit(-1); end
   end

   -- (3) Set up the input, output and error parameters
   infilename = opt_filename
   if opt_filename=="-" then infilename = ""; end   -- stdin
   outfilename = ""				    -- stdout
   errfilename = "/dev/null"
   if OPTION["-all"] then errfilename = ""; end	    -- stderr

   -- (4) Set up what kind of encoding we want done on the output
   encoder = "color"
   if OPTION["-json"] then encoder = "json"
   elseif OPTION["-nocolor"] then encoder = "text"; end
   success, msg = lapi.configure(CL_ENGINE, {encoder=encoder})
   if not success then io.write(msg, "\n"); os.exit(-1); end

   -- (5) Iterate through the lines in the input file
   local match_function = lapi.match_file
   if eval then match_function = lapi.eval_file; end
   local ok, cin, cout, cerr = match_function(CL_ENGINE, infilename, outfilename, errfilename)
   if not ok then io.write(cin, "\n"); os.exit(-1); end

   -- (6) Print summary
   if not QUIET then
      local fmt = "Rosie: %d input items processed (%d matches, %d items unmatched)\n"
      io.stderr:write(string.format(fmt, cin, cout, cerr))
   end
end

----------------------------------------------------------------------------------------
-- Do stuff
----------------------------------------------------------------------------------------

process_command_line_options()

if OPTION["-verbose"] then
   QUIET = false;
else
   QUIET = true;
end

if OPTION["-help"] then
   if #arg > 1 then print("Warning: ignoring extraneous command line arguments"); end
   help()
   os.exit()
end

if OPTION["-patterns"] then
   greeting();
   if opt_pattern then print("Warning: ignoring extraneous command line arguments (pattern and/or filename)"); end
   if opt_manifest then
      local success, msg = lapi.load_manifest(CL_ENGINE, opt_manifest)
      if not success then
	 io.stdout:write(msg, "\n")
	 os.exit(-4)
      end
   end
   local ok, env = lapi.get_env(CL_ENGINE)
   if not ok then error(env); end		    -- api call failed, env is message
   common.print_env(json.decode(env))		    -- inefficient FIXME!
   os.exit()
end

if OPTION["-repl"] then
   greeting();
   if opt_pattern then print("Warning: ignoring extraneous command line arguments (pattern and/or filename)"); end
   if opt_manifest then
      local ok, msg = lapi.load_manifest(CL_ENGINE, opt_manifest)
      if not ok then io.write(msg, "\n"); os.exit(-4); end
   end
   repl(CL_ENGINE)
   os.exit()
end

if (not opt_pattern) then
   greeting()
   print("Missing pattern and/or filename arguments")
   print(usage_message)
else
   if not QUIET then greeting(); end
   process_pattern_against_file()
end
