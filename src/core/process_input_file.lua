-- -*- Mode: Lua; -*-                                                                             
--
-- process_input_file.lua   Using the engine abstraction, process an entire file of input
--
-- © Copyright IBM Corporation 2016, 2017.
-- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
-- AUTHOR: Jamie A. Jennings

local process_input_file = {}

local engine = require "engine"

local function open3(e, infilename, outfilename, errfilename)
   if type(infilename)~="string" then e:_error("bad input file name"); end
   if type(outfilename)~="string" then e:_error("bad output file name"); end
   if type(errfilename)~="string" then e:_error("bad error file name"); end   
   local infile, outfile, errfile, msg
   if #infilename==0 then infile = io.stdin;
   else infile, msg = io.open(infilename, "r"); if not infile then e:_error(msg); end; end
   if #outfilename==0 then outfile = io.stdout
   else outfile, msg = io.open(outfilename, "w"); if not outfile then e:_error(msg); end; end
   if #errfilename==0 then errfile = io.stderr;
   else errfile, msg = io.open(errfilename, "w"); if not errfile then e:_error(msg); end; end
   return infile, outfile, errfile
end

local function engine_process_file(e, expression, flavor, eval_flag, infilename, outfilename, errfilename, wholefileflag)
   if type(eval_flag)~="boolean" then e:_error("bad eval flag"); end
   --
   -- Set up pattern to match.  Always compile it first, even if we are going to call eval later.
   -- This is so that we report errors uniformly at this point in the process, instead of after
   -- opening the files.
   --
   local r = e:compile(expression, flavor)

   local infile, outfile, errfile = open3(e, infilename, outfilename, errfilename);
   local inlines, outlines, errlines = 0, 0, 0;
   local trace, leftover, m;
   local nextline
   if wholefileflag then
      nextline = function()
		    if wholefileflag then
		       wholefileflag = false;
		       return infile:read("a")
		    end
		 end
   else
      nextline = infile:lines();
   end
   local o_write, e_write = outfile.write, errfile.write
   local l = nextline(); 
   while l do
      local _
      if eval_flag then _, _, trace = e:eval(expression, l); end
      m, leftover = r:match(l);
      -- What to do with leftover?  User might want to see it.
      if trace then o_write(outfile, trace, "\n"); end
      if m then
	 o_write(outfile, m, "\n")
	 outlines = outlines + 1
      else --if not eval_flag then
	 e_write(errfile, l, "\n")
	 errlines = errlines + 1
      end
      if trace then o_write(outfile, "\n"); end
      inlines = inlines + 1
      l = nextline(); 
   end -- while
   infile:close(); outfile:close(); errfile:close();
   return inlines, outlines, errlines
end

function process_input_file.match(e, expression, flavor, infilename, outfilename, errfilename, wholefileflag)
   return engine_process_file(e, expression, flavor, false, infilename, outfilename, errfilename, wholefileflag)
end

function process_input_file.eval(e, expression, flavor, infilename, outfilename, errfilename, wholefileflag)
   return engine_process_file(e, expression, flavor, true, infilename, outfilename, errfilename, wholefileflag)
end

return process_input_file
