---- -*- Mode: Lua; -*- 
----
---- repl.lua     Rosie interactive pattern development repl
----
---- (c) 2016, Jamie A. Jennings
----

api = require "api"
common = require "common"

local repl_patterns = [==[
      alias validchars = { [:alnum:] / [_%!$@:.,~-] }
      path = "/"? { validchars+ {"/" validchars+}* }
      load = ".load" path
      manifest = ".manifest" path
      match = ".match" expression "," quoted_string
      eval = ".eval" expression "," quoted_string
      on_off = "on" / "off"
      debug = ".debug" on_off?
      patterns = ".patterns"
      clear = ".clear"
      help = ".help"
      command = load / manifest / match / eval / debug / patterns / clear / help
      input = command / statement / identifier
]==]

repl_engine = api.new_engine("repl")
api.load_file(repl_engine, "src/rosie-core.rpl")
api.load_string(repl_engine, repl_patterns)
api.set_match_exp(repl_engine, "input")

repl_prompt = "Rosie> "

local function print_match(m, p, len, eval_p)
   if m then 
      table.print(m)
      if (p <= len) then
	 print("Warning: unmatched characters at end of input")
      end
   else
      local msg = "Repl: No match"
      if not eval_p then
	 msg = msg .. ((debug and " (turn debug off to hide the match trace)")
		    or " (turn debug on to show the match trace)")
      end
      print(msg)
   end
end

function repl(eid)
   local ok, en = api.ping_engine(eid)
   if (not ok) then
      error("Argument to repl not an engine id: " .. tostring(eid))
   end
   io.write(repl_prompt)
   local s = io.stdin:read("l")
   if s==nil then io.write("\nExiting\n"); return nil; end -- EOF, e.g. ^D at terminal
   if s~="" then					   -- blank line input
      local ok, m, left = api.match(repl_engine, s)
      if not m then
	 io.write("Repl: syntax error.  Enter a statement or a command.  Type .help for help.\n")
      else
	 -- valid input to repl
	 if left > 0 then
	    -- not all input consumed
	    io.write('Warning: ignoring extraneous input "', s:sub(-left), '"\n')
	 end
	 local _, _, _, subs, subidx = common.decode_match(m)
	 local name, pos, id, subs, subidx = common.decode_match(subs[subidx])
	 if name=="identifier" then
	    local ok, def = api.get_definition(eid, id)
	    if ok then 
	       io.write(def, "\n")
	    else
	       io.write("Repl: undefined identifier ", id, "\n")
	       if id=="help" then
		  io.write("  Hint: use .help to get help\n")
	       end
	    end
	 elseif name=="command" then
	    local cname, cpos, ctext, csubs, csubidx = common.decode_match(subs[subidx])
	    if cname=="load" or cname=="manifest" then
	       local pname, ppos, path = common.decode_match(csubs[csubidx])
	       local results, msg
	       if cname=="load" then 
		  results, msg = api.load_file(eid, path)
	       else -- manifest command
		  results, msg = api.load_manifest(eid, path)
	       end
	       if results then
		  io.write("Loaded ", msg, "\n")
	       else
		  io.write(msg, "\n")
	       end
	    elseif cname=="debug" then
	       if csubs then
		  local _, _, arg = common.decode_match(csubs[csubidx])
		  debug = (arg=="on")
	       end -- if csubs
	       io.write("Debug is ", (debug and "on") or "off", "\n")
	    elseif cname=="patterns" then
	       local ok, env = api.get_env(eid)
	       if ok then
		  io.write(json.decode(env))	    -- !@# temporary
	       else
		  io.write("Repl: error accessing pattern environment\n")
	       end
	    elseif cname=="clear" then
	       io.write("UNIMPLEMENTED!\n")	    -- !@# temporary
	    elseif cname=="match" or cname =="eval" then
	       local ename, epos, exp = common.decode_match(csubs[csubidx])
	       -- parsing strips the quotes off when exp is only a literal string, but compiler
	       -- needs them there.  this is inelegant.  sigh.
	       if ename=="string" then exp = '"'..exp..'"'; end
	       local tname, tpos, input_text = common.decode_match(csubs[csubidx+1])
	       input_text = compile.unescape_string(input_text)
	       local pat, msg = compile.compile_command_line_expression(exp, en.env)
	       if not pat then io.write(msg);
	       else
		  -- if compile failed, pat will be nil and errors will already have been
		  -- explained. 
		  en.program = {pat}
		  local m, pos = en:run(input_text)
		  if cname=="match" then
		     if debug and (not m) then
			local _, _, msg = eval.eval(exp, input_text, 1, en.env, true)
			io.write(msg)
		     end
		  else
		     -- must be eval
		     local _, _, msg = eval.eval(exp, input_text, 1, en.env)
		     io.write(msg)
		  end
		  print_match(m, pos, #input_text, (cname=="eval"))
	       end -- if pat
	    elseif cname=="help" then
	       repl_help();
	    else
	       io.write("Repl: unimplemented command\n")
	    end -- switch on command
	 elseif name=="alias_" or name=="assignment_" or name=="grammar_" then
	    local result, msg = compile.compile(text, en.env);
	    if not result then io.write(msg); end
	 else
	    io.write("Repl: internal error\n")
	 end -- switch on type of input received
      end
   end
   repl(en)
end

function repl_help()
   io.write("Commands are: \n")
   io.write(" Help text will go here (sorry) \n")
end

