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
local readline = require "readline"
list = require "list"

local repl_patterns = [==[
      rpl_expression = expression
      rpl_exp_placeholder = {!{quoted_string $} .}+
      parsed_args = rpl_exp_placeholder? quoted_string?
      path = {![[:space:]] {"\\ " / .}}+		    -- escaped spaces allowed
      load = ".load" path?
      manifest = ".manifest" path?
      args = .*
      match = ".match" args 
      eval = ".eval" args
      on_off = "on" / "off"
      debug = ".debug" on_off?
      patterns = ".patterns" identifier?
      star = "*"
      clear = ".clear" (identifier / star)?
      help = ".help"
      badcommand = {"." .+}
      command = load / manifest / match / eval / debug / patterns / clear / help / badcommand
      input = command / statement / identifier
]==]

repl_engine = lapi.new_engine({name="repl"})
lapi.load_file(repl_engine, "$sys/src/rpl-core.rpl")
lapi.load_string(repl_engine, repl_patterns)

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
   --io.write(repl_prompt)
   --local s = io.stdin:read("l")
   local s = readline.readline(repl_prompt)
   if s==nil then io.write("\nExiting\n"); return nil; end -- EOF, e.g. ^D at terminal
   if s~="" then					   -- blank line input
      local ok, msg = lapi.configure_engine(repl_engine, {expression="input", encode=false})
      if not ok then io.write("Repl internal error: ", msg); os.exit(-6); end
      local m, left = lapi.match(repl_engine, s)
      if not m then
	 io.write("Repl: syntax error.  Enter a statement or a command.  Type .help for help.\n")
      else
	 -- valid input to repl
	 if left > 0 then
	    -- not all input consumed
	    io.write('Warning: ignoring extraneous input "', s:sub(-left), '"\n')
	 end
	 local _, _, _, subs = common.decode_match(m)
	 local name, pos, text, subs = common.decode_match(subs[1])
	 if name=="identifier" then
	    local def = lapi.get_environment(en, text)
	    if def then io.write(def.binding, "\n")
	    else
	       io.write(string.format("Repl: undefined identifier %s\n", text))
	       if text=="help" then
		  io.write("  Hint: use .help to get help\n")
	       elseif (text=="exit") or (text=="quit") then
		  io.write("  Hint: use ^D (control-D) to exit\n")
	       end
	    end
	 elseif name=="command" then
	    local cname, cpos, ctext, csubs = common.decode_match(subs[1])
	    if cname=="load" or cname=="manifest" then
	       if not csubs then
		  io.write("Command requires a file name\n")
	       else
		  local pname, ppos, path = common.decode_match(csubs[1])
		  local ok, messages, full_path
		  if cname=="load" then 
		     ok, messages, full_path = lapi.load_file(en, path)
		  else -- manifest command
		     ok, messages, full_path = lapi.load_manifest(en, path)
		  end
		  if ok then
		     if messages then list.foreach(print, messages); end
		     io.write("Loaded ", full_path, "\n")
		  else
		     io.write(messages, "\n")
		  end
	       end -- if csubs[1]
	    elseif cname=="debug" then
	       if csubs then
		  local _, _, arg = common.decode_match(csubs[1])
		  debug = (arg=="on")
	       end -- if csubs
	       io.write("Debug is ", (debug and "on") or "off", "\n")
	    elseif cname=="patterns" then
	       local env = lapi.get_environment(en)
	       local filter = nil
	       if csubs then
	          _,_,filter,_ = common.decode_match(csubs[1])
	       end
	       common.print_env(env, filter)
	    elseif cname=="clear" then
	       if csubs and csubs[1] then
		  local name, pos, id, subs = common.decode_match(csubs[1])
		  if (name=="identifier") then
		     if en.env[id] then en.env[id] = nil -- abstraction breakage?
		     else io.write("Repl: undefined identifier: ", id, "\n"); end
		  elseif (name=="star") then
		     lapi.clear_environment(en)
		     io.write("Pattern environment cleared\n")
		  else
		     io.write("Repl: internal error while processing clear command\n")
		  end
	       else -- missing argument
		  io.write("Error: supply the identifier to clear, or * for all\n")
	       end
	    elseif cname=="match" or cname =="eval" then
	       if (not csubs) or (not csubs[1]) then
		  io.write("Missing expression and input arguments\n")
	       else
		  local ename, epos, argtext = common.decode_match(csubs[1])
		  assert(ename=="args")
		  local ok, msg = lapi.configure_engine(repl_engine, {expression='parsed_args'})
		  if not ok then io.write("Repl internal error: ", msg); os.exit(-6); end
		  local m, msg = lapi.match(repl_engine, argtext)
		  assert(next(m)=="parsed_args")
		  local msubs = m and m.parsed_args.subs
		  if (not m) or (not msubs) or (not msubs[1]) then
		     io.write("Expected a match expression follwed by a quoted input string\n")
		  elseif (not msubs[2]) or (not msubs[2].literal) then
		     io.write("Missing quoted string (after the match expression)\n")
		  else
		     local mname, mpos, mtext, msubs = common.decode_match(m)
		     local ename, epos, exp_string = common.decode_match(msubs[1])
		     local astlist, original_astlist = parse_and_explain(exp_string)
		     if not astlist then
			io.write(original_astlist, "\n") -- error message
		     else
			-- parsing strips the quotes off when exp is only a literal string, but compiler
			-- needs them there.  this is inelegant.  sigh
			assert((type(astlist)=="table") and astlist[1])
			local ename, epos, exp = common.decode_match(original_astlist[1])
			if ename=="literal" then exp = '"'..exp..'"'; end
			local tname, tpos, input_text = common.decode_match(msubs[2])
			input_text = common.unescape_string(input_text)
			local ok, msg = lapi.configure_engine(en, {expression=exp, encode="json"})
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
			end -- failed to configure engine to do the match
		     end -- could not parse out the expression and input string from the repl input
		  end -- if unable to parse argtext into: stuff "," quoted_string
	       end -- if pat
	    elseif cname=="help" then
	       repl_help();
	    else
	       io.write("Repl: Unknown command (Type .help for help.)\n")
	    end -- switch on command
	 elseif name=="alias_" or name=="assignment_" or name=="grammar_" then
	    local ok, messages = lapi.load_string(en, text);
	    if not ok then io.write(messages, "\n")
	    elseif messages then
	       for _, msg in ipairs(messages) do if msg then io.write(msg, "\n"); end; end
	    end
	 else
	    io.write("Repl: internal error\n")
	 end -- switch on type of input received
      end
   end
   readline.add_history(s)
   repl(en)
end

local help_text = [[
   Rosie Help

   At the prompt, you may enter a command, an identifier name (to see its
   definition), or an RPL statement.  Commands start with a dot (".") as
   follows:

   .load path                    load RPL file (see note below)
   .manifest path                load manifest file (see note below)
   .match exp quoted_string      match RPL exp against (quoted) input data
   .eval exp quoted_string       show full evaluation (trace)
   .debug {on|off}               show debug state; with an argument, set it
   .patterns [filter]            list patterns in the environment
   .clear <id>                   clear the pattern definition of <id>, * for all
   .help                         print this message

   Note on paths to RPL and manifest files: A filename may begin with $sys,
   which refers to the Rosie install directory, or $(VAR), which is the value of
   the environment variable $VAR.  For filenames inside a manifest file, $lib
   refers to the directory containing the manifest file.

   EOF (^D) will exit the read/eval/print loop.
]]      

function repl_help()
   io.write(help_text)
end

