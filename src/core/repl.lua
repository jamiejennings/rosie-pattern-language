---- -*- Mode: Lua; -*-                                                                           
----
---- repl.lua     Rosie interactive pattern development repl
----
---- © Copyright IBM Corporation 2016, 2017.
---- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
---- AUTHOR: Jamie A. Jennings

-- FUTURE:
--   - Create a .import command which does a re-loading?  Or .unload to remove a package?


local repl = {}

-- N.B. 'rosie' is a global defined by init and loaded by cli.lua, which calls the repl

local rosie = require "rosie"
local readline = rosie.import "readline"

local common = require "common"
local ustring = require "ustring"
local ui = require "ui"
local environment = require "environment"
local lpeg = require "lpeg"
local os = require "os"

-- We support a basic form of tilde expansion when the user enters a file name.  (Only ~/... is
-- supported, not the ~user/... syntax.)
local ok, HOMEDIR = pcall(os.getenv, "HOME")
if (not ok) or (type(HOMEDIR)~="string") then HOMEDIR = ""; end

local repl_patterns = [==[
      comma_or_quoted_string = ","? word.dq
      rpl_exp_placeholder = {!{comma_or_quoted_string $} .}+
      parsed_args = rpl_exp_placeholder? ","? word.dq?
      path = {![[:space:]] {"\\ " / .}}+		    -- escaped spaces allowed
      load = ".load" path?
      arg = [:^space:]+
      args = .*
      match = ".match" args 
      trace = ".trace" args
      fulltrace = ".fulltrace" args
      on_off = "on" / "off"
      debug = ".debug" on_off?
      alnum = { [[:alpha:]] / [[:digit:]] }
      package = rpl.packagename
      list = ".list" arg?
      star = "*"
      undefine = ".undefine" rpl.identifier? --(rpl.identifier / star)?
      help = ".help"
      badcommand = {"." .+}
      command = load / match / trace / fulltrace / debug / list / undefine / help / badcommand
      statements = rpl.rpl_statements
      identifier = ~ rpl.identifier ~ $
      input = command / identifier / statements
]==]

local repl_engine = rosie.engine.new("repl")
repl.repl_engine = repl_engine
repl_engine:set_libpath(ROSIE_LIBPATH)
assert(repl_engine:load("import rosie/rpl_1_2 as rpl, word"))
assert(repl_engine:load(repl_patterns))
input_rplx = repl_engine:compile("input")
assert(input_rplx, "internal error: input_rplx failed to compile")
pargs_rplx = repl_engine:compile("parsed_args")
assert(pargs_rplx, "internal error: pargs_rplx failed to compile")

local repl_prompt = "Rosie> "

local function print_match(m, left, trace_command)
   if m then 
      assert(type(m)=="table")
      io.write(util.table_to_pretty_string(m, false, true, true), "\n")
      if (left > 0) then
	 print(string.format("Warning: %d unmatched characters at end of input", left))
      end
   else
      if not trace_command then
	 if not debug then
	    print("No match  [Turn debug on to show the trace output]")
	 else
	    print("No match  [Turn debug off to hide the trace output]")
	 end
      end
   end
end

function repl.repl(en)
   local ok = rosie.engine.is(en)
   if (not ok) then
      error("Argument to repl is not a live engine: " .. tostring(en))
   end
   local s = readline.readline(repl_prompt)
   if s==nil then io.write("\nExiting\n"); return nil; end -- EOF, e.g. ^D at terminal
   if s~="" then					   -- blank line input
      local m, left = input_rplx:match(s, 1)
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
	    local packagename, localname = common.split_id(text)
	    local def = en.env:lookup(localname, packagename)
	    if def then
	       local props = ui.properties(text, def)
	       io.write(props.binding, "\n")
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
	    if cname=="load" then
	       if not csubs then
		  io.write("Command requires a file name\n")
	       else
		  local pname, ppos, path = common.decode_match(csubs[1])
		  if path:sub(1,2)=="~/" then
		     path = HOMEDIR .. path:sub(2)
		  end
		  local ok, pkgname, messages, full_path
		  ok, pkgname, messages = en:loadfile(path, true)
		  if messages then
		     for _,msg in ipairs(messages) do
			print(violation.tostring(msg))
		     end
		  end
		  if ok then
		     if pkgname then
			io.write("Loaded package ", pkgname, " from ", path, "\n")
		     else
			io.write("Loaded ", path, "\n")
		     end
		  end -- if ok
	       end -- if csubs[1]
	    elseif cname=="debug" then
	       if csubs then
		  local _, _, arg = common.decode_match(csubs[1])
		  debug = (arg=="on")
	       end -- if csubs
	       io.write("Debug is ", (debug and "on") or "off", "\n")
	    elseif cname=="list" then
	       local filter = "*"
	       if csubs and csubs[1] then
	          filter = csubs[1].data
	       end
	       local tbl, msg = ui.to_property_table(en.env, filter)
	       if tbl then ui.print_props(tbl)
	       else io.write(msg, "\n")
	       end
	    elseif cname=="undefine" then
	       if csubs and csubs[1] then
		  local name, pos, id, subs = common.decode_match(csubs[1])
		  local situation = en.env:unbind(id)
		  if situation then
		     io.write("Repl: removed binding, revealing inherited binding: ",
			      tostring(situation), '\n')
		  elseif situation==nil then
		     io.write("Repl: undefined identifier: ", id, "\n")
		  end
	       else -- missing argument
		  io.write("Error: missing the identifier to undefine\n")
	       end
	    elseif cname=="match" or cname=="trace" or cname=="fulltrace" then
	       local trace_command = (cname ~= "match")
	       if (not csubs) or (not csubs[1]) then
		  io.write("Missing expression and input arguments\n")
	       else
		  local ename, epos, argtext = common.decode_match(csubs[1])
		  assert(ename=="args")
		  local m, msg = pargs_rplx:match(argtext)
		  assert(m.type=="parsed_args")
		  local msubs = m and m.subs
		  if (not m) or (not msubs) or (not msubs[1]) then
		     io.write("Expected a match expression followed by a quoted input string\n")
		  elseif (not msubs[2]) or (not msubs[2].type=="literal") then
		     io.write("Missing quoted string (after the match expression)\n")
		  else
		     local mname, mpos, mtext, msubs = common.decode_match(m)
		     local ename, epos, exp_string = common.decode_match(msubs[1])
		     local errs = {}
		     local a = en.compiler.parse_expression(common.source.new{text=exp_string}, errs)
		     if not a then
			local err_string = table.concat(map(violation.tostring, errs), "\n")
			io.write(err_string, "\n")
		     else
			-- Assert that 'a' is a record, and assume it's an AST record
			assert(recordtype.parent(a))
			-- Parsing strips the quotes off when exp is only a literal string, but compiler
			-- needs them there.  This is inelegant.  <sigh>
			local str
			if ast.literal.is(a) then
			   --str = '"' .. ustring.unescape_string(a.value) .. '"'
			   str = '"' .. (a.value) .. '"'
			else
			   str = exp_string
			end
			local tname, tpos, input_text = common.decode_match(msubs[2])
			assert(tname=="word.dq")
			assert(input_text:sub(1,1)=='"' and input_text:sub(-1)=='"')
			--input_text = ustring.unescape(input_text:sub(2, -2))
			input_text = input_text:sub(2, -2)
			-- Compile the expression given in the command
			local rplx, errs = en:compile(str)
			if not rplx then
			   local err_string = table.concat(map(violation.tostring, errs), "\n")
			   io.write(err_string, "\n")
			else
			   local m, left = rplx:match(input_text)
			   if (debug and (not m)) or trace_command then
			      local tracetype = (cname=="trace") and "condensed" or "full"
			      local ok, matched, tr = en:trace(str, input_text, 1, tracetype)
			      if not ok then
				 io.write("Internal error: expression did not compile\n")
			      else
				 if (not trace_command) and tr:sub(-9)=="\nNo match" then
				    tr = tr:sub(1,-10)
				 end
				 print(tr)
			      end
			   end
			   print_match(m, left, trace_command)
			end -- did exp compile
		     end -- could not parse out the expression and input string from the repl input
		  end -- if unable to parse argtext into: stuff "," quoted_string
	       end -- if pat
	    elseif cname=="help" then
	       repl.repl_help();
	    else
	       io.write("Repl: Unknown command (Type .help for help.)\n")
	    end -- switch on command
	 elseif name=="statements" then
	    local ok, pkg, messages = en:load(text);
	    if (not ok) and (#messages == 0) then
	       io.write("Repl: invalid rpl statement.  Further detail is unavailable.\n")
	       io.write("Please consider reporting this as a bug.\n")
	    end
	    if #messages > 0 then
	       local err_string = table.concat(map(violation.tostring, messages), "\n")
	       io.write(err_string, "\n")
	    end
	 else
	    io.write("Repl: internal error (name was '" .. tostring(name) .. "')\n")
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

   .load path                 load RPL file 
   .match exp quoted_string   match RPL exp against (quoted) input data
   .trace exp quoted_string   show full trace output of the matching process
   .debug {on|off}            show debug state; with an argument, set it
   .list [filter]             list patterns that match filter string (* for all)
   .undefine <id>             remove the binding to <id>
   .help                      print this message

   EOF (^D) will exit the read/eval/print loop.
]]      

function repl.repl_help()
   io.write(help_text)
end

return repl
