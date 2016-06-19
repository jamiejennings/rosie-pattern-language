---- -*- Mode: Lua; -*-                                                                           
----
---- repl.lua     Rosie interactive pattern development repl
----
---- © Copyright IBM Corporation 2016.
---- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
---- AUTHOR: Jamie A. Jennings

lapi = require "lapi"
common = require "common"
json = require "cjson"

local repl_patterns = [==[
      rpl_expression = expression
      path = {![:space:] {"\\ " / .}}+		    -- escaped spaces allowed
      load = ".load" path
      manifest = ".manifest" path
      match = ".match" rpl_expression "," quoted_string
      eval = ".eval" rpl_expression "," quoted_string
      on_off = "on" / "off"
      debug = ".debug" on_off?
      patterns = ".patterns"
      clear = ".clear" identifier?
      help = ".help"
      command = load / manifest / match / eval / debug / patterns / clear / help
      input = command / statement / identifier
]==]

repl_engine = lapi.new_engine("repl")
lapi.load_file(repl_engine, "src/rpl-core.rpl")
lapi.load_string(repl_engine, repl_patterns)
lapi.configure_engine(repl_engine, {expression="input", encoder="json"})

repl_prompt = "Rosie> "

local function print_match(m, left, eval_p)
   if m then 
      io.write(util.prettify_json(m), "\n")
      if (left > 0) then
	 print(string.format("Warning: %d unmatched characters at end of input", left))
      end
   else
      local msg = "Repl: No match"
      if not eval_p then
	 msg = msg .. ((debug and "  (turn debug off to hide the match evaluation trace)")
		    or "  (turn debug on to show the match evaluation trace)")
      end
      print(msg)
   end
end

function repl(en)
   local ok = lapi.inspect_engine(en)
   if (not ok) then
      error("Argument to repl is not a live engine: " .. tostring(en))
   end
   io.write(repl_prompt)
   local s = io.stdin:read("l")
   if s==nil then io.write("\nExiting\n"); return nil; end -- EOF, e.g. ^D at terminal
   if s~="" then					   -- blank line input
      local m, left = lapi.match(repl_engine, s)
      if not m then
	 io.write("Repl: syntax error.  Enter a statement or a command.  Type .help for help.\n")
      else
	 -- valid input to repl
	 if left > 0 then
	    -- not all input consumed
	    io.write('Warning: ignoring extraneous input "', s:sub(-left), '"\n')
	 end
	 m = json.decode(m)			    -- inefficient, but let's not worry right now
	 local _, _, _, subs = common.decode_match(m)
	 local name, pos, text, subs = common.decode_match(subs[1])
	 if name=="identifier" then
	    local def, msg = lapi.get_binding(en, text)
	    if def then io.write(def, "\n")
	    else
	       io.write("Repl: ", msg, "\n")
	       if text=="help" then
		  io.write("  Hint: use .help to get help\n")
	       end
	    end
	 elseif name=="command" then
	    local cname, cpos, ctext, csubs = common.decode_match(subs[1])
	    if cname=="load" or cname=="manifest" then
	       local pname, ppos, path = common.decode_match(csubs[1])
	       local ok, messages, full_path
	       if cname=="load" then 
		  ok, messages, full_path = lapi.load_file(en, path)
	       else -- manifest command
		  ok, messages, full_path = lapi.load_manifest(en, path)
	       end
	       if ok then
		  if messages then foreach(print, messages); end
		  io.write("Loaded ", full_path, "\n")
	       else
		  io.write(messages, "\n")
	       end
	    elseif cname=="debug" then
	       if csubs then
		  local _, _, arg = common.decode_match(csubs[1])
		  debug = (arg=="on")
	       end -- if csubs
	       io.write("Debug is ", (debug and "on") or "off", "\n")
	    elseif cname=="patterns" then
	       local env = lapi.get_environment(en)
	       common.print_env(env)
	    elseif cname=="clear" then
	       if csubs and csubs[1] then
		  local name, pos, id, subs = common.decode_match(csubs[1])
		  assert(name=="identifier")
		  if en.env[id] then en.env[id] = nil -- abstraction breakage?
		  else io.write("Repl: undefined identifier: ", id, "\n"); end
	       else -- no identifier followed the clear command
		  lapi.clear_environment(en)
		  io.write("Pattern environment cleared\n")
	       end
	    elseif cname=="match" or cname =="eval" then
	       local ename, epos, exp = common.decode_match(csubs[1])
	       -- parsing strips the quotes off when exp is only a literal string, but compiler
	       -- needs them there.  this is inelegant.  sigh.
	       if ename=="string" then exp = '"'..exp..'"'; end
	       local tname, tpos, input_text = common.decode_match(csubs[2])
	       input_text = common.unescape_string(input_text)
	       local ok, msg = lapi.configure_engine(en, {expression=exp, encoder="json"})
	       if not ok then
		  io.write(msg, "\n");		    -- syntax and compile errors
	       else
		  local m, left = lapi.match(en, input_text)
		  if cname=="match" then
		     if debug and (not m) then
			local match, leftover, trace = lapi.eval(en, input_text)
			io.write(trace, "\n")
		     end
		  else
		     -- must be eval
		     local match, leftover, trace = lapi.eval(en, input_text)
		     io.write(trace, "\n")
		  end
		  print_match(m, left, (cname=="eval"))
	       end -- if pat
	    elseif cname=="help" then
	       repl_help();
	    else
	       io.write("Repl: unimplemented command\n")
	    end -- switch on command
	 elseif name=="alias_" or name=="assignment_" or name=="grammar_" then
	    local ok, messages = lapi.load_string(en, text);
	    if not ok then io.write(messages, "\n")
	    else for _, msg in ipairs(messages) do if msg then io.write(msg); end; end
	    end
	 else
	    io.write("Repl: internal error\n")
	 end -- switch on type of input received
      end
   end
   repl(en)
end

local help_text = [[
Help
At the prompt, you may enter a command, an identifier name (to see its definition),
or an RPL statement.  Commands start with a dot (".") as follows:

    .load path                      load RPL file (see note below)
    .manifest path                  load manifest file (see note below)
    .match exp, quoted_string       match RPL expression against (quoted) input data
    .eval exp, quoted_string        show full evaluation (trace)
    .debug {on|off}                 show debug state; with an argument, set it
    .patterns                       list patterns in the environment
    .clear                          clear the pattern environment
    .help                           print this message

    Note on paths to RPL and manifest files:  A filename may begin with $sys, which
    refers to the Rosie install directory, or $(VAR), which is the value of the environment
    variable $VAR.  For filenames inside a manifest file, $lib refers to the directory
    containing the manifest file.

    EOF (^D) will exit the read/eval/print loop.
]]      

function repl_help()
   io.write(help_text)
end

