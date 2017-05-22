-- -*- Mode: Lua; -*-                                                                             
--
-- command-common.lua
--
-- © Copyright IBM Corporation 2017.
-- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
-- AUTHOR: Jamie A. Jennings

local p = {}

function p.set_encoder(rosie, en, name)
   local encode_fcn = rosie.encoders[name]
   if encode_fcn==nil then
      local msg = "invalid output encoder: " .. tostring(name)
      if ROSIE_DEV then error(msg)
      else io.write(msg, "\n"); os.exit(-1); end
   end
   en:output(encode_fcn)
end

function p.load_string(en, input)
   local ok, results, messages = pcall(en.load, en, input)
   if not ok then
      if ROSIE_DEV then error(results)
      else io.write("Cannot load rpl: \n", results); os.exit(-1); end
   end
   return results, messages
end

function p.load_file(en, filename)
   local ok, messages = pcall(en.loadfile, en, filename)
   if not ok then
      if ROSIE_DEV then error("Cannot load file: \n" .. messages)
      else io.write("Cannot load file: \n", messages); os.exit(-1); end
   end
   return ok, messages
end


function p.setup_engine(en, args)
   -- (1a) Load whatever is specified in ~/.rosierc ???


   -- (1b) Load an rpl file
   if args.rpls then
      for _,filename in pairs(args.rpls) do
	 if args.verbose then
	    io.stdout:write("Compiling additional file ", filename, "\n")
	 end
	 -- nosearch is true so that files given on command line are not searched for
	 local success, msg = pcall(en.loadfile, en, filename, true)
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
	 local success, msg = p.load_string(en, stm)
	 if not success then
	    io.stdout:write(msg, "\n")
	    os.exit(-4)
	 end
      end
   end
   -- (2) Compile the expression
   local compiled_pattern
   if args.pattern then
      local expression
      if args.fixed_strings then
	 expression = '"' .. args.pattern:gsub('"', '\\"') .. '"' -- FUTURE: rosie.expr.literal(arg[2])
      else
	 expression = args.pattern
      end
      local flavor = (args.command=="grep") and "search" or "match"
      local ok, msgs
      ok, compiled_pattern, msgs = pcall(en.compile, en, expression, flavor)
      if not ok then
	 io.stdout:write(compiled_pattern, "\n")
	 os.exit(-4)
      elseif not compiled_pattern then
	 io.stdout:write(table.concat(msgs, '\n'), '\n')
	 os.exit(-4)
      end
   end
   return compiled_pattern			    -- could be nil
end

return p


