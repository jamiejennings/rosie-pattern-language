-- -*- Mode: Lua; -*-                                                                             
--
-- command-match.lua         Implements the cli commands 'match' and 'grep'
--
-- © Copyright IBM Corporation 2017.
-- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
-- AUTHOR: Jamie A. Jennings

local match = {}
local cli_common = import("command-common")

-- FUTURE: use lua_filesystem equivalent instead of this:
local function readable_file(fn)
   if fn=="" then return true; end			    -- "" means standard input
   local f, msg = io.open(fn, "r")
   if not f then
      assert (type(msg)=="string")
      if msg:find("No such file") then return nil, "No such file"
      elseif msg:find("Permission denied") then return nil, "Permission denied"
      else return nil, "Cannot open file"; end
   end
   -- now we have a file, but it could be a directory
   local try, msg, code = f:read(0)
   if not try then
      -- not sure we can count on the undocumented numeric codes.
      -- if msg is nil then the file is readable, but is empty.
      if (type(msg)=="string") then
	 if msg:find("Is a directory") then return nil, "Is a directory"
	 else return nil, "Cannot read file"; end
      end
   end
   f:close()
   return true
end

local infilename, outfilename, errfilename = nil, nil, nil

function match.process_pattern_against_file(rosie, en, args, compiled_pattern, infilename)
   assert(compiled_pattern, "Rosie: missing pattern?")
   assert(engine_module.rplx.is(compiled_pattern), "Rosie: compiled pattern not rplx?")

   -- Set up the input, output and error parameters
   if infilename=="-" then infilename = ""; end	    -- stdin
   outfilename = ""				    -- stdout
   errfilename = "/dev/null"
   if args.all then errfilename = ""; end	            -- stderr
   
   -- Set up what kind of encoding we want done on the output
   local default_encoder = (args.command=="grep") and "line" or "color"
   cli_common.set_encoder(rosie, en, args.encoder or default_encoder)
   
   local ok, msg = readable_file(infilename)
   local printable_infilename = (infilename ~= "") and infilename or "stdin"
   if (args.verbose) or (#args.filename > 1) then
      if ok then io.write(printable_infilename, ":\n"); end    -- print name of file before its output
   end
   if not ok then
      io.stderr:write(printable_infilename, ": ", msg, "\n")
      return
   end
   
   -- Iterate through the lines in the input file
   local match_function = (args.command=="trace") and en.tracefile or en.matchfile

   local ok, cin, cout, cerr =
      pcall(match_function, en, compiled_pattern, infilename, outfilename, errfilename, args.wholefile)

   if not ok then io.write(cin, "\n"); return; end	-- cin is error message (a string) in this case
   
   -- (6) Print summary
   if args.verbose then
      local fmt = "Rosie: %d input item%s processed (%d matched, %d item%s unmatched)\n"
      local cin_plural = (cin ~= 1) and "s" or ""
      local cerr_plural = (cerr ~= 1) and "s" or ""
      io.stderr:write(string.format(fmt, cin, cin_plural, cout, cerr, cerr_plural))
   end
end

return match
