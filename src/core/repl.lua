---- -*- Mode: Lua; -*-                                                                           
----
---- repl.lua     Rosie interactive pattern development repl
----
---- © Copyright IBM Corporation 2016, 2017.
---- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
---- AUTHOR: Jamie A. Jennings

local repl = {}

-- N.B. 'rosie' is a global defined by init and loaded by run.lua, which calls the repl

--local lapi = require "lapi"
local common = require "common"
local json = require "cjson"
local list = require "list"
local readline = require "readline"

local repl_patterns = [==[
      rpl_expression = expression
      rpl_exp_placeholder = {!{quoted_string $} .}+
      parsed_args = rpl_exp_placeholder? quoted_string?
      path = {![[:space:]] {"\\ " / .}}+		    -- escaped spaces allowed
      load = ".load" path?
      manifest = ".manifest" path?
      args = .*
      match = ".match" args 
      trace = ".trace" args
      on_off = "on" / "off"
      debug = ".debug" on_off?
      alnum = { [[:alpha:]] / [[:digit:]] }
      patterns = ".patterns" { identifier / {alnum+} }?
      star = "*"
      clear = ".clear" (identifier / star)?
      help = ".help"
      badcommand = {"." .+}
      command = load / manifest / match / trace / debug / patterns / clear / help / badcommand
      input = command / statement / identifier
]==]

local repl_engine = rosie.engine.new("repl")
repl.repl_engine = repl_engine
rosie.file.load(repl_engine, "$sys/src/rpl-core.rpl", "rpl")
repl_engine:load(repl_patterns)

local repl_prompt = "Rosie> "

local function print_match(m, left, eval_p)
   if m then 
      io.write(util.prettify_json(m), "\n")
      if (left > 0) then
	 print(string.format("Warning: %d unmatched characters at end of input", left))
      end
   else
      local msg = "Repl: No match"
      if not eval_p then
	 msg = msg .. ((debug and "  (turn debug off to hide the trace output)")
		    or "  (turn debug on to show the trace output)")
      end
      print(msg)
   end
end

function repl.repl(en)
   local ok = rosie.engine.is(en)
   if (not ok) then
      error("Argument to repl is not a live engine: " .. tostring(en))
   end
   en:output(rosie.encoders.json)
   local s = readline.readline(repl_prompt)
   if s==nil then io.write("\nExiting\n"); return nil; end -- EOF, e.g. ^D at terminal
   if s~="" then					   -- blank line input
      local m, left = repl_engine:match("input", s)
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
	    local def = en:lookup(text)
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
		     ok, messages, full_path = pcall(rosie.file.load, en, path, "rpl")
		  else -- manifest command
		     ok, messages, full_path = pcall(rosie.file.load, en, path, "manifest")
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
	       local env = en:lookup()
	       local filter = nil
	       if csubs then
	          _,_,filter,_ = common.decode_match(csubs[1])
	       end
	       common.print_env(env, filter)
	    elseif cname=="clear" then
	       if csubs and csubs[1] then
		  local name, pos, id, subs = common.decode_match(csubs[1])
		  if (name=="identifier") then
		     if not en:clear(id) then io.write("Repl: undefined identifier: ", id, "\n"); end
		  elseif (name=="star") then
		     en:clear()
		     io.write("Pattern environment cleared\n")
		  else
		     io.write("Repl: internal error while processing clear command\n")
		  end
	       else -- missing argument
		  io.write("Error: supply the identifier to clear, or * for all\n")
	       end
	    elseif cname=="match" or cname =="trace" then
	       if (not csubs) or (not csubs[1]) then
		  io.write("Missing expression and input arguments\n")
	       else
		  local ename, epos, argtext = common.decode_match(csubs[1])
		  assert(ename=="args")
		  local m, msg = repl_engine:match("parsed_args", argtext)
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
			local ok, m, left = pcall(en.match, en, exp, input_text)
			if not ok then
			   io.write(m, "\n") -- syntax and compile errors
			else
			   if cname=="match" then
			      if debug and (not m) then
				 local match, leftover, trace = en:tracematch(exp, input_text)
				 io.write(trace, "\n")
			      end
			   else
			      local match, leftover, trace = en:tracematch(exp, input_text)
			      io.write(trace, "\n")
			   end
			   print_match(m, left, (cname=="trace"))
			end -- did the pcall to en.match succeed or not
		     end -- could not parse out the expression and input string from the repl input
		  end -- if unable to parse argtext into: stuff "," quoted_string
	       end -- if pat
	    elseif cname=="help" then
	       repl.repl_help();
	    else
	       io.write("Repl: Unknown command (Type .help for help.)\n")
	    end -- switch on command
	 elseif name=="alias_" or name=="assignment_" or name=="grammar_" then
	    local ok, messages = pcall(en.load, en, text);
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
   repl.repl(en)
end

local help_text = [[
   Rosie Help

   At the prompt, you may enter a command, an identifier name (to see its
   definition), or an RPL statement.  Commands start with a dot (".") as
   follows:

   .load path                    load RPL file (see note below)
   .manifest path                load manifest file (see note below)
   .match exp quoted_string      match RPL exp against (quoted) input data
   .trace exp quoted_string      show full trace output of the matching process
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

function repl.repl_help()
   io.write(help_text)
end

return repl
