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

local function dequote(str)
   if str:sub(1,1)=='"' then
      assert(str:sub(-1)=='"', 
	     "malformed quoted string that the grammar should have caught: " .. str)
      return common.unescape_string(str:sub(2,-2))
   end
   return str
end

function c1.read_module(dequoted_importpath)
   if #dequoted_importpath==0 then return nil, nil, "nil import path"; end
   local try = "rpl" .. common.dirsep .. dequoted_importpath .. ".rpl"
   return try, util.readfile(try)
end

function c1.process_import_decl(typ, pos, text, specs, fin, parser, env, modtable)
   local compiled_imports = {}
   local prefix, modenv
   for _,spec in ipairs(specs) do
      local typ, pos, text, subs, fin = decode_match(spec)
      assert(subs and subs[1], "missing package name to import?")
      local typ, pos, importpath = decode_match(subs[1])
      importpath = dequote(importpath)
      io.write("*\t", "import |", importpath, "|")
      if subs[2] then
	 typ, pos, prefix = decode_match(subs[2])
	 assert(typ=="packagename" or typ=="dot")
	 io.write(" as ", prefix)
      else
	 _, prefix = util.split_path(importpath, "/")
      end
      modenv = modtable[importpath]
      if modenv then
	 io.write("  (Found in modtable)\n");
      else
	 local results, msgs
	 local fullpath, source, err = c1.read_module(importpath)
	 if source then
	    io.write("  (Found in filesystem at " .. fullpath .. ")\n");
	    print("COMPILING MODULE " .. importpath)	    
	    results, msgs, modenv =
	       c1.compile_module(parser, source, env, modtable, importpath)
	    if not results then error(table.concat(msgs, "\n")); end
	    modtable[importpath] = modenv
	 else
	    -- we could not find the module source
	    error(err)
	 end
      end
      table.insert(compiled_imports,
		   {importpath=importpath,
		    fullpath=fullpath,
		    prefix=prefix,
		    env=modenv,
		    results=results or {},
		    messages=msgs or {}})
   end -- for
   return compiled_imports
end

function c1.compile_local(ast, gmr, source, env)
   assert(not gmr, "rpl grammar allowed a local decl inside a grammar???")
   local typ, _, _, subs = decode_match(ast)
   assert(typ=="local_")
   local name, pos, text = decode_match(subs[1])
   print("->", "local " .. name .. ": " .. text)
   local pat = c0.compile_ast(subs[1], source, env)
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

----------------------------------------------------------------------------------------
-- Coroutine body
----------------------------------------------------------------------------------------

-- compile_module enforces the structure of an rpl module:
--     rpl_module = language_decl? package_decl? import_decl* statement* ignore
--
-- We could parse a module using that rpl_module pattern, but we can give better
-- error messages this way.

function c1.compile_module(parser, source, env, modtable, importpath)
   local astlist, orig_astlist, messages = parser(source)
   if not astlist then return nil, messages; end
   -- modtable is the global module table (one per engine)
   -- importpath is the filesystem path from $ROSIE_PATH down to and including the source file
   local thispkg
   local results, messages = {}, {}
   local i = 1
   if not astlist[i] then return results, {"Empty module"}; end
   local typ, pos, text, subs, fin = common.decode_match(astlist[i])
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
      typ, pos, text, subs, fin = common.decode_match(astlist[i])
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

      local compiled_modules = c1.process_import_decl(typ, pos, text, subs, fin, parser, env, modtable)

      -- Below we process the compiled_modules table.
      -- Each imported module is reified as a binding in env that maps the prefix to its module env
      --   ** This way, we can in future treat the module as a first class object.
      --   ** But we must prohibit rebinding of this name (and we will prohibit
      --      rebinding names in general, except in the repl).

      for _, mod in ipairs(compiled_modules) do
	 if environment.lookup(env, mod.prefix) then
	    table.insert(messages, "REBINDING "..mod.prefix) -- TODO: make this an error
	 end
	 environment.bind(env, mod.prefix, mod.env)
	 print("-> binding module prefix: " .. mod.prefix)
	 -- TODO: do we need to keep results at all?
	 for _, result in ipairs(mod.results) do table.insert(results, result); end
	 for _, message in ipairs(mod.messages) do table.insert(messages, message); end
      end

      i=i+1;
      if not astlist[i] then
	 table.insert(messages, "Empty module (nothing after import declaration(s))")
	 return results, messages
      end
      typ, pos, text, subs, fin = common.decode_match(astlist[i])
   end
   repeat
      results[i], messages[i] = c1.compile_ast(astlist[i], source, env)
      if not messages[i] then messages[i] = false; end -- keep messages a proper list: no nils
      i=i+1
   until not astlist[i]
   return results, messages, env
end



return c1
