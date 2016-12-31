-- -*- Mode: Lua; -*-                                                                             
--
-- process_input_file.lua   Using the engine abstraction, process an entire file of input
--
-- © Copyright IBM Corporation 2016.
-- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
-- AUTHOR: Jamie A. Jennings

local process_input_file = {}

local function engine_error(e, msg)
   error(string.format("Engine %s (%s): %s", e._name, e._id, tostring(msg)), 0)
end

local function open3(e, infilename, outfilename, errfilename)
   if type(infilename)~="string" then engine_error(e, "bad input file name"); end
   if type(outfilename)~="string" then engine_error(e, "bad output file name"); end
   if type(errfilename)~="string" then engine_error(e, "bad error file name"); end   
   local infile, outfile, errfile, msg
   if #infilename==0 then infile = io.stdin;
   else infile, msg = io.open(infilename, "r"); if not infile then error(msg, 0); end; end
   if #outfilename==0 then outfile = io.stdout
   else outfile, msg = io.open(outfilename, "w"); if not outfile then error(msg, 0); end; end
   if #errfilename==0 then errfile = io.stderr;
   else errfile, msg = io.open(errfilename, "w"); if not errfile then error(msg, 0); end; end
   return infile, outfile, errfile
end

local function engine_process_file(e, expression, eval_flag, grep_flag, infilename, outfilename, errfilename, wholefileflag)
   if type(eval_flag)~="boolean" then engine_error(e, "bad eval flag"); end
   if type(grep_flag)~="boolean" then engine_error(e, "bad grep flag"); end
   local ok, infile, outfile, errfile = pcall(open3, e, infilename, outfilename, errfilename);
   if not ok then return false, infile; end	    -- infile is the error message in this case

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
   local match = (grep_flag and e.grep) or e.match
   local l = nextline(); 
   while l do
      local _
      if eval_flag then _, _, trace = e:eval(expression, l); end
      m, leftover = match(e, expression, l);
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

function process_input_file.match(e, expression, infilename, outfilename, errfilename, wholefileflag)
   return engine_process_file(e, expression, false, false, infilename, outfilename, errfilename, wholefileflag)
end

function process_input_file.grep(e, expression, infilename, outfilename, errfilename, wholefileflag)
   return engine_process_file(e, expression, false, true, infilename, outfilename, errfilename, wholefileflag)
end

function process_input_file.eval(e, expression, infilename, outfilename, errfilename, wholefileflag)
   return engine_process_file(e, expression, true, false, infilename, outfilename, errfilename, wholefileflag)
end

return process_input_file
