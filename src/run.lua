---- -*- Mode: Lua; -*- 
----
---- run.lua
----
---- (c) 2015, Jamie A. Jennings
----

-- This lua script must be called with the variable ROSIE_HOME set to be the full directory of the
-- rosie installation (not a relative path such as one starting with . or ..), and SCRIPTNAME set
-- to arg[0] of the shell script that invoked this code.

package.path = ROSIE_HOME .. "/src/?.lua"
package.cpath = ROSIE_HOME .. "/lib/?.so"

ROSIE_VERSION = io.lines(ROSIE_HOME.."/VERSION")();

common = require "common"
compile = require "compile"
eval = require "eval"
require "bootstrap"
bootstrap()

require "manifest"
require "color-output"
local json = require "cjson"

local function greeting()
   io.stderr:write("This is Rosie v" .. ROSIE_VERSION .. "\n")
end

local valid_options = {"-help", "-patterns", "-verbose", "-json", "-nooutput", "-nocolor",
		       "-repl", "-manifest", "-grep", "-debug"}

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

local option = {}				    -- array indexed by option name
local last_option = 0				    -- index of last command line option found
local manifest_arg = false			    -- previous arg was "-manifest"
for i,v in ipairs(arg) do
   if manifest_arg then
      -- previous arg was "-manifest" so we can skip over the next arg, which is manifest filename
      manifest_arg = false;
   else
      if valid_option_is(v) then
	 option[v] = arg[i+1] or true;
	 last_option = i;
	 if v=="-manifest" then
	    last_option = i+1;		      -- only this option takes an arg
	    manifest_arg = true;	      -- skip the next arg, which is the manifest filename
	 end
      elseif v:sub(1,1)=="-" then
	 -- arg starts with a dash but is not a valid option
	 io.write("Rosie: invalid command line option ", v, "\n")
	 io.write(usage_message, "\n")
	 os.exit(-1)
      end
   end -- if manifest arg
end -- for each command line arg

if (#arg==0) or (not (option["-help"] or option["-patterns"] or option["-repl"]) and (last_option > #arg-2)) then
   greeting()
   print(usage_message)
   os.exit(-1)
end

if option["-verbose"] then
   QUIET = false
else
   QUIET = true
end

if option["-help"] then
   greeting()
   print("Rosie help:")
   print(usage_message)
   print()
   print("  -help           prints this message")
   print("  -verbose        output warnings and other informational messages (errors will still be shown)")
   print("  -repl           start Rosie in the interactive mode (read-eval-print loop)")
   print("  -patterns       read manifest file, compile patterns, show pattern list (but process no input)")
   print("  -json           output in JSON")
   print("                  (the default is terminal window output, with recognized items shown in color")
   print("  -nooutput       generate no output to standard out; useful when interested only in unparsed lines")
   print("                  (information and errors, including unparsed input, are sent to standard error")
   print("  -nocolor        do not output the escape sequences that show color text in terminal windows")
   print("  -debug          output a detailed listing of how the pattern matched the input;")
   print("                  this feature generates LOTS of output, so best to use it on ONE LINE OF INPUT;")
   print("  -grep           emulate grep, but with RPL, by searching for all occurrences of <pattern> (interpreted in RAW mode) in the input")
   print("  -manifest <fn>  load the manifest file <fn> instead of the default " .. (ROSIE_HOME.."/MANIFEST"))
   print()
   print("  <pattern>       RPL expression, which may be the name of a defined pattern, against which each line will be matched")
   print("  <fn>            (filename) name of the file of text input to be processed line by line")
   print()
   print("Notes: ")
   print("(1) lines from the input file for which the pattern does NOT match are written to stderr so they can be redirected, e.g. to /dev/null")
   print("(2) the -debug option currently does not work with the -grep option")
   print("(3) to prevent any manifest file from loading, supply a single dash as the filename argument: -manifest -")
   print()
   os.exit(-1)
end

local manifest = option["-manifest"] or (option["-grep"] and (ROSIE_HOME.."/GREP-MANIFEST")) or (ROSIE_HOME.."/MANIFEST")
if manifest=="-" then manifest=nil; end

local patterns_loaded, pattern_list

if option["-patterns"] then
   local pattern_list = (manifest and do_manifest(ENGINE, manifest)) or {}
   local patterns_loaded = #pattern_list
   greeting();
   print()
   print(patterns_loaded .. " patterns loaded via manifest: ")
   print();
   print(string.format("%-26s %-15s %-8s", "Pattern", "Kind", "Color"))
   print("-------------------------- --------------- --------")
   local kind
   for _,v in ipairs(pattern_list) do 
      local kind = (ENGINE.env[v].alias and "alias") or "definition";
      local color = colormap[v] or "";
      print(string.format("%-26s %-15s %-8s", v, kind, color))
   end
   os.exit(-1)
end

-- Say Hello
if not QUIET then 
   greeting();
end

----------------------------------------------------------------------------------------
-- Read-eval-print loop
----------------------------------------------------------------------------------------

if option["-repl"] then
   if manifest then do_manifest(ENGINE, manifest); end
   require("repl")
   repl()
   os.exit()
end

----------------------------------------------------------------------------------------
-- Below, we get things ready to compile the pattern on the command line and process the
-- input file.
----------------------------------------------------------------------------------------

-- Must supply at least the pattern and filename args
if #arg < 2 then
   print(usage_message)
   os.exit(-1)
end
   
if option["-grep"] and option["-debug"] then
   print("Error: currently, the -grep option and the -debug option are incompatible.  Use one or the other.")
   os.exit(-1)
end

if manifest then do_manifest(ENGINE, manifest); end
local pattern = arg[#arg-1]
local filename = arg[#arg]

debug = false;
-- Attempt to compile.  If we fail to get a peg, we can exit because the errors will already have
-- been displayed.
local peg
if option["-debug"] then
   peg = 12345					    -- any non-nil value
   debug = true;
elseif option["-grep"] then
   peg = grep_match_compile_to_peg(pattern, ENGINE.env)
else
   local pat = compile.compile_command_line_expression(pattern, ENGINE.env) -- returns a pattern object
   peg = pat and pat.peg
end
if not peg then os.exit(-1); end		    -- compilation errors were already printed

local match_function;
if option["-grep"] then
   match_function = grep_match_peg
elseif option["-debug"] then
   match_function = nil
else
   match_function = peg.match
end

-- match returns [entire_match, [named sub matches]]
-- grep_match_peg returns a list of matches

if option["-grep"] then
   default_output_function = 
      function(t) 
	 if t[1] then
	    for _,v in ipairs(t) do
	       color_print_leaf_nodes(v)
	    end
	    io.write("\n")
	 end
      end
else
   default_output_function =
      function(t)
	 color_print_leaf_nodes(t)
	 io.write("\n")
      end
end

if option["-nooutput"] or option["-debug"] then
   output_function = function(t) return; end;
elseif option["-json"] then
   output_function = function(t) io.write(json.encode(t), "\n"); end;
elseif option["-nocolor"] then
   output_function =
      ( option["-grep"] and
	function(t)
	 if t[1] then
	    for i,v in ipairs(t) do
	       local name, pos, text, subs, subidx = common.decode_match(v);
	       io.write(text);
	    end;
	    io.write("\n");
	 end  -- if anything to print
      end)
   or function(t)
	 local name, pos, text, subs, subidx = common.decode_match(t);
	 io.write(text, "\n")
      end
else
   output_function = default_output_function;
end

----------------------------------------------------------------------------------------
-- Iterate through the lines in the input file
----------------------------------------------------------------------------------------

local nextline = io.lines(filename);
local lines = 0;
local l = nextline(); 
local t;
while l do
   if debug then
      local m = eval.eval(pattern, l, 1, ENGINE.env)
   else
      t = match_function(peg, l);
      if t then
	 output_function(t)
      else
	 -- pattern did not match, so echo the input line
	 if not QUIET then
	    io.stderr:write("Pattern did not match: ", l, "\n");
	 end
      end
   end
   lines = lines + 1;
   l = nextline(); 
end

if not QUIET then
   io.stderr:write("Rosie: " .. lines .. " input lines processed.\n")
end


