-- -*- Mode: Lua; -*-                                                                             
--
-- c1.lua    rpl compiler internals for rpl 1.1
--
-- © Copyright IBM Corporation 2017.
-- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
-- AUTHOR: Jamie A. Jennings

local c1 = {}
local c0 = require "c0"

local string = require "string"
local lpeg = require "lpeg"
local common = require "common"
local decode_match = common.decode_match

function c1.process_package_decl(typ, pos, text, subs, fin)
   assert(typ=="package_decl")
   local typ, pos, text = decode_match(subs[1])
   assert(typ=="packagename")
   print("In package " .. text)
   return text					    -- return package name
end

function c1.read_module(importpath)
   -- This is a HACK right now
   -- TODO: replace dots in importpath with common.dirsep
   if importpath:sub(1,1)=='"' then
      assert(importpath:sub(-1)=='"', 
	     "malformed input path that grammar should have caught: " .. importpath)
      importpath = common.unescape_string(importpath:sub(2,-2))
   end
   if #importpath==0 then return nil, nil, "nil import path"; end
   local try = "rpl1.1" .. common.dirsep .. importpath .. ".rpl"
   return try, util.readfile(try)
end

local compile_module = false;				    -- forward reference

function c1.process_import_decl(typ, pos, text, specs, fin, parser, env, modtable)
   local compiled_imports = {}
   for _,spec in ipairs(specs) do
      local typ, pos, text, subs, fin = decode_match(spec)
      assert(subs and subs[1], "missing package name to import?")
      local typ, pos, importpath = decode_match(subs[1])
      io.write("*\t", "import ", importpath)
      if subs[2] then
	 local typ, pos, prefix = decode_match(subs[2])
	 assert(typ=="packagename" or typ=="dot")
	 io.write(" as ", prefix)
      end
      if modtable[importpath] then
	 io.write("  (Found in modtable)\n");
      else
	 local fullpath, source, err = c1.read_module(importpath)
	 if source then
	    io.write("  (Found in filesystem at " .. fullpath .. ")\n");
	    local results, msgs, env =
	       compile_module(parser, source, env, modtable, importpath)
	    if not results then error(table.concat(msgs, "\n")); end
	    table.insert(compiled_imports,
			 {importpath=importpath,
			  fullpath=fullpath,
			  prefix=prefix,
			  env=env,
			  results=results,
			  messages=msgs})
	 else
	    -- we could not find the module source
	    error(err)
	 end
      end
   end -- for
   return compiled_imports
end

function c1.compile_local(ast, gmr, source, env)
   assert(not gmr, "rpl grammar allowed a local decl inside a grammar???")
   local typ, _, _, subs = decode_match(ast)
   assert(typ=="local_")
   local name, pos, text = decode_match(subs[1])
   print("->", "local " .. name .. ": " .. text)
   local pat = c0.compile_binding(subs[1], false, source, env)
   pat.exported = false;
   return pat
end

function c1.compile_ast(ast, source, env)
   assert(type(ast)=="table", "Compiler: first argument not an ast: "..tostring(ast))
   local functions = {"compile_ast";
		      local_ = c1.compile_local;
		      binding=c0.compile_binding;
		      new_grammar=c0.compile_grammar;
		      exp=c0.compile_exp;
		      default=c0.compile_exp;
		   }
   return common.walk_ast(ast, functions, false, source, env)
end

---------------------------------------------------------------------------------------------------
-- Launch a co-routine to compile an astlist
---------------------------------------------------------------------------------------------------

local function make_compile(compile_astlist)
   return function(parser, source, env, modtable, importpath)
	     assert(type(parser)=="function", "Internal error: compile: parser not a function")
--	     assert(type(astlist)=="table", "Internal error: compile: astlist not a table")
--	     assert(type(original_astlist)=="table", "Internal error: compile: original_astlist not a table")
	     assert(type(source)=="string", "Internal error: compile: source not a string")
	     assert(type(env)=="table", "Internal error: compile: env not a table")
	     assert(type(modtable)=="table")
	     assert(type(importpath)=="string")
	     local c = coroutine.create(compile_astlist)
	     local no_lua_error, results, messages =
		coroutine.resume(c, parser, source, env, modtable, importpath)
	     if no_lua_error then
		-- Return results and compilation messages
		if results then
		   assert(type(messages)=="table")
		   for i, pat in ipairs(results) do
-- TODO: syntax-expand should save each original_ast as part of the new ast (or something)
--		      if common.pattern.is(pat) then pat.original_ast = original_astlist[i]; end
		   end
		   return results, messages		    -- message may contain compiler warnings
		else
		   assert(type(messages)=="string")
		   return false, {messages}		    -- message is a string in this case
		end
	     else
		error("Internal error (compiler): " .. tostring(results))
	     end
	  end
end

----------------------------------------------------------------------------------------
-- Coroutine body
----------------------------------------------------------------------------------------

-- compile_module enforces the structure of an rpl module:
--     rpl_module = language_decl? package_decl import_decl* statement* ignore
--
-- We could parse a module using that rpl_module pattern, but it's easier to give useful
-- error messages this way.

compile_module = function(parser, source, env, modtable, importpath)
   local astlist, orig_astlist, messages = parser(source)
   if not astlist then return nil, messages; end
   -- modtable is the global module table (one per engine)
   -- importpath is the filesystem path from $ROSIE_PATH down to and including the source file
   local thispkg
   local results, messages = {}, {}
   local i = 1
   if not astlist[i] then return results, {"Empty module"}; end
   local typ, pos, text, subs, fin = decode_match(astlist[i])
   assert(typ~="language_decl", "language declaration should be handled in preparse/parse")
   if typ=="package_decl" then
      -- create/set the compilation environment according to the package name,
      -- maybe issuing a warning if the env exists already
      thispkg = c1.process_package_decl(typ, pos, text, subs, fin)
      results[i] = thispkg; messages[i] = false
      i=i+1;
      if not astlist[i] then
	 table.insert(messages, "Empty module (nothing after package declaration)")
	 return results, messages
      end
      typ, pos, text, subs, fin = decode_match(astlist[i])
   end
   -- If there is a package_decl, then this code is a module.  It gets its own fresh
   -- environment, and it is registered (by its importpath) in the per-engine modtable.
   -- Otherwise, if there is no package decl, then the code is compiled in the default, or
   -- "top level" environment.  Nothing special to do in that case.
   if thispkg then
      assert(not modtable[importpath],
	     "module " .. importpath .. " already compiled and loaded")
      env = environment.new()			    -- shadowing the env argument
      modtable[importpath] = env
   end
   while typ=="import_decl" do
      -- If the module has been compiled, it will have an entry in modtable.  We can just
      -- point to it. (Since modules are immutable, they can be shared.)
      -- Otherwise, find the module in the filesystem, then compile it into a fresh env.

	 local compiled_modules =
	    c1.process_import_decl(typ, pos, text, subs, fin, parser, env, modtable)

	 --results[i], messages[i] =
	 -- TODO:
	 -- (1) process the compiled_modules table
	 -- (2) create a binding in env that maps the prefix to its module env
	 --     ** this way, we can in future treat the module as a first class object
	 --     ** but we must prohibit rebinding of this name (and we will prohibit
	 --        rebinding names in general, except in the repl)
	 --     ** now we do NOT need the OPENMODULES table!  yay!!!
	 
      -- Finally, in both cases we must make the imported package's exports accessible in this env.
      -- TODO: make the exports of modtable[importpath] available in this env.

      i=i+1;
      if not astlist[i] then
	 table.insert(messages, "Empty module (nothing after import declaration(s))")
	 return results, messages
      end
      typ, pos, text, subs, fin = decode_match(astlist[i])
   end
   repeat
      results[i], messages[i] = c1.compile_ast(astlist[i], source, env)
      if not messages[i] then messages[i] = false; end -- keep messages a proper list: no nils
      i=i+1
   until not astlist[i]
   return results, messages, env
end

c1.compile_module = make_compile(compile_module)

return c1
