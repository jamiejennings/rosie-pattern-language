-- -*- Mode: Lua; -*-                                                                             
--
-- command-parser.lua
--
-- © Copyright IBM Corporation 2017.
-- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
-- AUTHORS: Jamie A. Jennings, Kevin Zander

----------------------------------------------------------------------------------------
-- Parser for command line args
----------------------------------------------------------------------------------------

local p = {}


-- create Parser
function p.create(rosie)
   local argparse = assert(rosie.import("argparse"), "failed to load argparse package")
   local parser = argparse("rosie", "Rosie " .. rosie.info().ROSIE_VERSION)
   parser:add_help(false)
   parser:require_command(false)
   --:epilog("Additional information.")
   -- global flags/options can go here
   -- -h,--help is generated automatically
   -- usage message is generated automatically
   parser:flag("--version", "Print rosie version")
   :action(function(args,_,exceptions)
	      io.write(ROSIE_VERSION, "\n")
	      os.exit()
	   end)
   parser:flag("--verbose", "Output additional messages")
   :default(false)
   :action("store_true")
   parser:option("--rpl", "Inline RPL statements")
   :args(1)
   :count("*") -- allow multiple RPL statements
   :target("statements") -- set name of variable index (args.statements)
   parser:option("-f --file", "Load an RPL file")
   :args(1)
   :count("*") -- allow multiple loads of a file
   :target("rpls") -- set name of variable index (args.rpls)

   local output_choices={}
   for k,v in pairs(rosie.encoders) do
      if type(k)=="string" then table.insert(output_choices, k); end
   end
   local output_choices_string = output_choices[1]
   for i=2,#output_choices do
      output_choices_string = output_choices_string .. ", " .. output_choices[i]
   end

   parser:option("--libpath", "Directories to search for rpl modules")
   :args(1)
   :target("libpath")				    -- args.libpath

   parser:option("-o --output", "Output style, one of: " .. output_choices_string)
   :convert(function(a)
	       -- validation of argument, will fail if not in choices array
	       for j=1,#output_choices do
		  if a == output_choices[j] then
		     return a
		  end
	       end
	       return nil
	    end)
   :args(1) -- consume argument after option
   :target("encoder")
   
   -- target variable for commands
   parser:command_target("command")
   local cmd_info = parser:command("help")
   :description("Print this help message")
   -- grep command
   local cmd_grep = parser:command("grep")
   :description("In the style of Unix grep, match the pattern anywhere in each input line")
   -- info command
   local cmd_info = parser:command("info")
   :description("Print rosie installation information")
   -- patterns command
   local cmd_patterns = parser:command("list")
   :description("List installed patterns")
   cmd_patterns:argument("filter")
   :description("Filter pattern names that have substring 'filter'")
   :args("?")
   -- match command
   local cmd_match = parser:command("match")
   :description("Match the given RPL pattern against the input")
   -- repl command
   local cmd_repl = parser:command("repl")
   :description("Start the read-eval-print loop for interactive pattern development and debugging")
   -- test command
   local cmd_test = parser:command("test")
   :description("Execute pattern tests written within the target rpl file(s)")
   cmd_test:argument("filenames", "RPL filenames")
   :args("+")
   -- expand command
   local cmd_expand = parser:command("expand")
   :description("Expand an rpl expression to see the input to the rpl compiler")
   :argument("expression")
   :args(1)
   -- trace command
   local cmd_trace = parser:command("trace")
   :description("Match while tracing all steps (generates MUCH output)")

   for _, cmd in ipairs{cmd_match, cmd_trace, cmd_grep} do
      -- match/trace/grep flags (true/false)
      cmd:flag("-w --wholefile", "Read the whole input file as single string")
      :default(false)
      :action("store_true")
      cmd:flag("-a --all", "Output non-matching lines to stderr")
      :default(false)
      :action("store_true")
      cmd:flag("-F --fixed-strings", "Interpret the pattern as a fixed string, not an RPL pattern")
      :default(false)
      :action("store_true")

      -- match/trace/grep arguments (required options)
      cmd:argument("pattern", "RPL pattern")
      cmd:argument("filename", "Input filename")
      :args("+")
      :default("-")			      -- in case no filenames are passed, default to stdin
      :defmode("arg")			      -- needed to make the default work
   end
   return parser
end

return p

