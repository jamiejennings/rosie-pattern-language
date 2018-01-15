-- -*- Mode: Lua; -*-                                                                             
--
-- cli-common.lua
--
-- © Copyright IBM Corporation 2017.
-- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
-- AUTHOR: Jamie A. Jennings

local p = {}

local violation = require "violation"
local list = require "list"
map = list.map

local write_error = function(...) io.stderr:write(...) end

function p.load_string(en, input)
   local ok, pkgname, messages = en:load(input)
   if not ok then
      local err_string = table.concat(map(violation.tostring, messages), "\n") .. "\n"
      if ROSIE_DEV then
	 error(err_string)
      else
	 write_error("Cannot load rpl: \n", err_string)
	 os.exit(-1)
      end
   end
   return ok, messages
end

function p.load_file(en, filename)
   local ok, pkgname, messages, actual_path = en:loadfile(filename)
   if not ok then
      if ROSIE_DEV then error("Cannot load file: \n" .. messages)
      else write_error("Cannot load file: \n", messages); os.exit(-1); end
   end
   return ok, messages
end

local function import_dependencies(en, a, msgs)
   local deps = en.compiler.dependencies_of(a)
   local all_ok = true
   for _, packagename in ipairs(deps) do
      local ok, actual_pkgname, errs = en:import(packagename, nil)
      if not ok then
	 if errs then
	    for _, err in ipairs(errs) do table.insert(msgs, err); end
	 else
	    io.stderr:write("Unspecified error importing ", tostring(packagename), '\n')
	 end
	 all_ok = false
      end
   end -- for each dependency
   return all_ok
end

function p.setup_engine(en, args)
   -- (1a) Load whatever is specified in ~/.rosierc ???

   -- (1b) Load an rpl file
   if args.rpls then
      for _,filename in pairs(args.rpls) do
	 if args.verbose then
	    io.stdout:write("Compiling additional file ", filename, "\n")
	 end
	 local success, pkgname, errs, actual_path = en.loadfile(en, filename)
	 if not success then
	    io.stdout:write("Error loading " .. tostring(filename) .. ":\n")
	    io.stdout:write(table.concat(map(violation.tostring, errs), "\n"), "\n")
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

	 local errs = {}
	 local AST = en.compiler.parse_block(common.source.new{text=stm}, errs)
	 if not AST then
	    write_error(table.concat(map(violation.tostring, errs), "\n"), "\n")
	    os.exit(-4)
	 end
	 
	 local ok = import_dependencies(en, AST, errs)
	 -- Nothing to do if the automated import fails, because the user may have included an
	 -- --rpl option with an "import ... as" statement, or an "import foo/bar/baz".

	 local success, msg = p.load_string(en, stm)
	 if not success then
	    write_error(msg, "\n")
	    os.exit(-4)
	 end
      end
   end
   -- (2) Compile the expression
   local compiled_pattern
   if args.pattern then
      local expression
      if args.fixed_strings then
	 -- FUTURE: rosie.expr.literal(arg[2])
	 expression = '"' .. args.pattern:gsub('"', '\\"') .. '"'
      else
	 expression = args.pattern
      end
      local errs = {}

      local AST = en.compiler.parse_expression(common.source.new{text=expression}, errs)
      if not AST then
	 write_error(table.concat(map(violation.tostring, errs), "\n"), "\n")
	 os.exit(-4)
      end

      if (args.command=="grep") then
	 -- FUTURE: rosie.expr.apply_macro("find", exp)
	 local findall = ast.ref.new{localname="findall"}
	 AST = ast.application.new{ref=findall,
				   arglist={ast.ambient_cook_exp(AST)},
				   sourceref=AST.sourceref}
      end

      local ok = import_dependencies(en, AST, errs)
      -- Nothing to do if the automated import fails, because the user may have included an
      -- --rpl option with an "import ... as" statement, or an "import foo/bar/baz".
      local ok, errs
      compiled_pattern, errs = en:compile(AST)
      if not compiled_pattern then
	 write_error(table.concat(map(violation.tostring, errs), "\n"), "\n")
	 os.exit(-4)
      end
   end
   return compiled_pattern
end

return p


