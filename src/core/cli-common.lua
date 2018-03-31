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

-- These MUST all be numbers so we can easily distinguish error results
p.ERROR_USAGE = -1
p.ERROR_INTERNAL = -2
p.ERROR_CONFIG = -3
p.ERROR_RESULT = -4

local write_error = function(...) io.stderr:write(...) end

function p.load_string(en, input)
   local ok, pkgname, messages = en:load(input)
   if not ok then
      local err_string = table.concat(map(violation.tostring, messages), "\n") .. "\n"
      write_error("Cannot load rpl: \n", err_string)
      return p.ERROR_CONFIG
   end
   return ok, messages
end

function p.load_file(en, filename)
   local ok, pkgname, messages, actual_path = en:loadfile(filename)
   if not ok then
      write_error("Cannot load file: \n", messages)
      return p.ERROR_CONFIG
   end
   return ok, messages
end

-- FUTURE: Change this to use en:block_dependencies(...)
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

function p.setup_engine(rosie, en, args)
   -- Load whatever is specified in ~/.rosierc, which may include setting the libpath
   local rcfile = rosie.default.rcfile
   local is_default = true
   if (not args.norcfile) then
      if args.rcfile then
	 rcfile = args.rcfile
	 is_default = false
      end
      local rc_exists, no_errors, messages =
	 en:execute_rcfile(rcfile,
			   rosie.engine.new,
			   is_default,
			   (is_default and "default") or "CLI")
      if messages then
	 for _, msg in ipairs(messages) do
	    common.warn(msg)
	 end
      end
   end

   -- Override the libpath if there is one on the command line
   if args.libpath then
      en:set_libpath(args.libpath, "CLI")
   end

   -- Override the colors if there is one on the command line
   if args.colors then
      en:set_encoder_parm("colors", args.colors, "CLI")
   end

   -- Load all rpl files given on the command line, if any
   if args.rpls then
      for _,filename in pairs(args.rpls) do
	 if args.verbose then
	    io.stdout:write("Compiling additional file ", filename, "\n")
	 end
	 local success, pkgname, errs, actual_path = en.loadfile(en, filename)
	 if not success then
	    io.stdout:write("Error loading " .. tostring(filename) .. ":\n")
	    io.stdout:write(table.concat(map(violation.tostring, errs), "\n"), "\n")
	    return p.ERROR_RESULT
	 end
      end
   end

   -- Load an rpl string given on the command line, if any
   if args.statements then
      for _,stm in pairs(args.statements) do
	 if args.verbose then
	    io.stdout:write(string.format("Compiling additional rpl code %q\n", stm))
	 end

	 local errs = {}
	 local AST = en.compiler.parse_block(common.source.new{text=stm}, errs)
	 if not AST then
	    write_error(table.concat(map(violation.tostring, errs), "\n"), "\n")
	    return p.ERROR_RESULT
	 end
	 
	 local ok = import_dependencies(en, AST, errs)
	 -- Nothing to do if the automated import fails, because the user may have included an
	 -- --rpl option with an "import ... as" statement, or an "import foo/bar/baz".

	 local success, msg = p.load_string(en, stm)
	 if not success then
	    write_error(msg, "\n")
	    return p.ERROR_RESULT
	 end
      end
   end

   -- Compile the expression given on the command line, if any
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
	 return p.ERROR_RESULT
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
	 return p.ERROR_RESULT
      end
   end -- if args.pattern
   return compiled_pattern
end

return p


