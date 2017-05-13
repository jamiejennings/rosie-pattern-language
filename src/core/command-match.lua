-- -*- Mode: Lua; -*-                                                                             
--
-- command-match.lua         Implements the cli commands 'match' and 'grep'
--
-- © Copyright IBM Corporation 2017.
-- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
-- AUTHOR: Jamie A. Jennings

local match = {}

function match.set_encoder(rosie, en, name)
   local encode_fcn = rosie.encoders[name]
   if encode_fcn==nil then
      local msg = "invalid output encoder: " .. tostring(name)
      if ROSIE_DEV then error(msg)
      else io.write(msg, "\n"); os.exit(-1); end
   end
   en:output(encode_fcn)
end

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
   match.set_encoder(rosie, en, args.encoder or default_encoder)
   
   local ok, msg = readable_file(infilename)
   if (args.verbose) or (#args.filename > 1) then
      if ok then io.write(infilename, ":\n"); end    -- print name of file before its output
   end
   if not ok then
      io.stderr:write(infilename, ": ", msg, "\n")
      return
   end
   
   -- Iterate through the lines in the input file
   local match_function = (args.command=="trace") and rosie.file.tracematch or rosie.file.match 

   local ok, cin, cout, cerr =
      pcall(match_function, en, compiled_pattern, nil, infilename, outfilename, errfilename, args.wholefile)

   if not ok then io.write(cin, "\n"); return; end	-- cin is error message (a string) in this case
   
   -- (6) Print summary
   if args.verbose then
      local fmt = "Rosie: %d input items processed (%d matches, %d items unmatched)\n"
      io.stderr:write(string.format(fmt, cin, cout, cerr))
   end
end

return match
