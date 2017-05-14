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

-- function c1.read_module(dequoted_importpath)
--    if #dequoted_importpath==0 then return nil, nil, "nil import path"; end
--    local try = "rpl" .. common.dirsep .. dequoted_importpath .. ".rpl"
--    return try, util.readfile(try)
-- end

-- function c1.process_import_decl(typ, pos, text, specs, fin, parser, env, modtable)
--    local compiled_imports = {}
--    local prefix, modenv
--    for _,spec in ipairs(specs) do
--       local typ, pos, text, subs, fin = decode_match(spec)
--       assert(subs and subs[1], "missing package name to import?")
--       local typ, pos, importpath = decode_match(subs[1])
--       importpath = common.dequote(importpath)
--       io.write("*\t", "import |", importpath, "|")
--       if subs[2] then
-- 	 typ, pos, prefix = decode_match(subs[2])
-- 	 assert(typ=="packagename" or typ=="dot")
-- 	 io.write(" as ", prefix)
--       else
-- 	 _, prefix = util.split_path(importpath, "/")
--       end
--       modenv = modtable[importpath]
--       if modenv then
-- 	 io.write("  (Found in modtable)\n");
--       else
-- 	 -- local results, msgs
-- 	 -- local fullpath, source, err = c1.read_module(importpath)
-- 	 -- if source then
-- 	 --    io.write("  (Found in filesystem at " .. fullpath .. ")\n");
-- 	 --    print("COMPILING MODULE " .. importpath)	    
-- 	 --    results, msgs, modenv =
-- 	 --       c1.compile_module(parser, source, env, modtable, importpath)
-- 	 --    if not results then error(table.concat(msgs, "\n")); end
-- 	 --    modtable[importpath] = modenv
-- 	 -- else
-- 	    -- we could not find the module source
-- 	    -- error(err)
-- 	 -- end
-- 	 assert(false, "module not loaded: " .. importpath .. "\n" .. debug.traceback())
--       end
--       table.insert(compiled_imports,
-- 		   {importpath=importpath,
-- 		    fullpath=fullpath,
-- 		    prefix=prefix,
-- 		    env=modenv,
-- 		    results=results or {},
-- 		    messages=msgs or {}})
--    end -- for
--    return compiled_imports
-- end

function c1.compile_local(ast, gmr, source, env)
   assert(not gmr, "rpl grammar allowed a local decl inside a grammar???")
   local typ, _, _, subs = decode_match(ast)
   assert(typ=="local_")
   local name, pos, text = decode_match(subs[1])
--   print("->", "local " .. name .. ": " .. text)
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

function c1.compile_module(parser, input, env, modtable, importpath)
   assert(environment.is(env))
   -- modtable is the global module table (one per engine)
   -- importpath is a relative filesystem path to the source file
   local source, astlist, orig_astlist, messages
   if type(input)=="string" then
      source = input
      astlist, orig_astlist, messages = parser(source)
   else
      astlist, orig_astlist, messages = input, input, {}
      source = "(no source)"
   end
   if not astlist then return nil, messages; end    -- syntax errors
   local thispkg
   local results, messages = {}, {}
   local i = 1
   if not astlist[i] then return nil, {"Empty module"}; end
   local typ, pos, text, subs, fin = common.decode_match(astlist[i])
   assert(typ~="language_decl", "language declaration should be handled in preparse/parse")
   if typ=="package_decl" then
      -- create/set the compilation environment according to the package name,
      -- maybe issuing a warning if the env exists already
      thispkg = c1.process_package_decl(typ, pos, text, subs, fin)
      i=i+1;
      if not astlist[i] then
	 return nil, {"Empty module (nothing after package declaration)"}
      end
      typ, pos, text, subs, fin = common.decode_match(astlist[i])
   end
   -- If there is a package_decl, then this code is a module.  It gets its own fresh
   -- environment, and it is registered (by its importpath) in the per-engine modtable.
   -- Otherwise, if there is no package decl, then the code is compiled in the default, or
   -- "top level" environment.  Nothing special to do in that case.
   if thispkg then
      assert(not modtable[importpath], "module " .. importpath .. " already compiled and loaded?")
      env = environment.new()			    -- purposely shadowing the env argument
   end
   -- Dependencies must have been compiled and imported before we get here, so we can skip over
   -- the import declarations.
   while typ=="import_decl" do
      i=i+1
      if not astlist[i] then return nil, {"Empty module (nothing after import declarations)"}; end
      typ, pos, text, subs, fin = common.decode_match(astlist[i])
   end -- while skipping import_decls
   repeat
      results[i], messages[i] = c1.compile_ast(astlist[i], source, env)
      if not messages[i] then messages[i] = false; end -- keep messages a proper list: no nils
      i=i+1
   until not astlist[i]
   -- success! save this env in the modtable, if we have an importpath.  pre-module system code
   -- (rpl 1.0 and rpl 0.0) will not use the modtable and will not supply an importpath.
   assert(environment.is(env))
   if modtable and importpath then modtable[importpath] = env; end
   return results, messages, env
end



return c1
