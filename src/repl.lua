---- -*- Mode: Lua; -*- 
----
---- repl.lua     Rosie interactive pattern development repl
----
---- (c) 2015, Jamie A. Jennings
----

local common = require "common"
local compile = require "compile"
local eval = require "eval"
local manifest = require "manifest"
require "engine"

-- Absolute path, e.g. ROSIE_HOME="/Users/jjennings/Work/Dev/rosie-dev"
assert(ROSIE_HOME, "The path to the Rosie installation, ROSIE_HOME, is not set")

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

repl_engine = engine("repl", {}, compile.new_env())
compile.compile_file(ROSIE_HOME.."/src/rosie-core.rpl", repl_engine.env)
compile.compile(repl_patterns, repl_engine.env)
repl_engine.program = {compile.compile_command_line_expression('input', repl_engine.env)}

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

function repl(en)
--   en = en or engine("engine for repl", {}, compile.new_env())
   io.write(repl_prompt)
   local s = io.stdin:read("l")
   if s==nil then io.write("\nExiting\n"); return nil; end -- EOF, e.g. ^D at terminal
   if s~="" then					   -- blank line input
      local m, pos = repl_engine:run(s)
      if not m then
	 io.write("Repl: syntax error.  Enter a statement or a command.  Type .help for help.\n")
      else
	 -- valid input to repl
	 if pos <= #s then
	    -- not all input consumed
	    io.write('Warning: ignoring extraneous input "', s:sub(pos), '"\n')
	 end
	 local _, _, _, subs, subidx = common.decode_match(m)
	 local name, pos, text, subs, subidx = common.decode_match(subs[subidx])
	 if name=="identifier" then
	    local id = text
	    local p = en.env[id]
	    if p then
	       io.write((p.alias and "alias ") or "",
			id,
			" = ",
			(p.ast and parse.reveal_ast(p.ast)) or "a built-in RPL pattern",
			"\n")
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
	       local filename = ((pname:sub(1,1)=="/" and "") or (ROSIE_HOME .. "/")) .. path
	       if cname=="load" then
		  compile.compile_file(filename, en.env)
		  io.write("Loaded ", filename, "\n")
	       else
		  manifest.process_manifest(en, filename)
	       end
	    elseif cname=="debug" then
	       if csubs then
		  local _, _, arg = common.decode_match(csubs[csubidx])
		  if arg=="on" then
		     debug = true;
		  else
		     debug = false;
		  end
	       end -- if csubs
	       io.write("Debug is ", (debug and "on") or "off", "\n")
	    elseif cname=="patterns" then
	       compile.print_env(en.env)
	    elseif cname=="clear" then
	       en.env = compile.new_env();
	       io.write("Environment cleared\n")
	    elseif cname=="match" or cname =="eval" then
	       local ename, epos, exp = common.decode_match(csubs[csubidx])
	       -- parsing strips the quotes off when exp is only a literal string, but compiler
	       -- needs them there.  this is inelegant.  sigh.
	       if ename=="string" then exp = '"'..exp..'"'; end
	       local tname, tpos, input_text = common.decode_match(csubs[csubidx+1])
	       input_text = compile.unescape_string(input_text)
	       local pat = compile.compile_command_line_expression(exp, en.env)
	       if pat then
		  -- if compile failed, pat will be nil and errors will already have been
		  -- explained. 
		  en.program = {pat}
		  local m, pos = en:run(input_text)
		  if cname=="match" then
		     if debug and (not m) then
			eval.eval(exp, input_text, 1, en.env, true)
		     end
		  else
		     -- must be eval
		     eval.eval(exp, input_text, 1, en.env)
		  end
		  print_match(m, pos, #input_text, (cname=="eval"))
	       end -- if pat
	    elseif cname=="help" then
	       repl_help();
	    else
	       io.write("Repl: unimplemented command\n")
	    end -- switch on command
	 elseif name=="alias_" or name=="assignment_" or name=="grammar_" then
	    compile.compile(text, en.env);
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

