-- -*- Mode: Lua; -*-                                                                             
--
-- loadpkg.lua   load an RPL module, which instantiates a run-time package
--
-- © Copyright IBM Corporation 2017, 2018.
-- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
-- AUTHOR: Jamie A. Jennings

local ast = require "ast"
local environment = require "environment"
local builtins = require "builtins"
local common = require "common"
local violation = require "violation"

-- Here is the bare beginnings of some compiler profiling:
local PROFILE = false
local PROFILE_PREFIX = "*prof* "
local function time(since)
   return (math.floor((os.clock() - since)*100000 + 0.5))/100 -- ms, rounded to nearest 1/100
end
local profile_print =
   function(...)
      io.stderr:write(PROFILE_PREFIX)
      for _,item in ipairs({...}) do
	 io.stderr:write(tostring(item))
      end
      io.stderr:flush()
   end
local profile_println =
   function(...)
      profile_print(...)
      io.stderr:write('\n')
      io.stderr:flush()
   end


local loadpkg = {}

-- 'validate_block' enforces the structure of an rpl module:
--     rpl_module = language_decl? package_decl? import_decl* statement* ignore
--
-- We could parse a module using that pattern, but we can give more detailed error messages this way.
-- Returns: success, table of messages
-- Side effects: fills in block.block_pdecl, block.block_ideclists; removes ALL decls from block.stmts
local function validate_block(a, messages)
   assert(ast.block.is(a))
   local stmts = a.stmts
   if not stmts[1] then
      table.insert(messages, violation.warning.new{who='loader', message="Empty input (no statements)", ast=a})
      return true
   elseif ast.pdecl.is(stmts[1]) then
      a.block_pdecl = table.remove(stmts, 1)
      common.note("load: in package " .. a.block_pdecl.name)
   end
   if not stmts[1] then
      table.insert(messages, violation.warning.new{who='loader',
						   message="Empty module (nothing after package declaration)",
						   ast=a})
      return true
   end
   a.block_ideclists = {}
   while stmts[1] and ast.ideclist.is(stmts[1]) do
      table.insert(a.block_ideclists, table.remove(stmts, 1))
   end
   if not stmts[1] then
      table.insert(messages, violation.info.new{who='loader',
						message="Module consists only of declarations (no bindings)",
						ast=a})
      return true
   end
   for _, s in ipairs(stmts) do
      if not ast.binding.is(s) then
	 local errmsg = "Declarations must appear before assignments"
	 if ast.ldecl.is(s) then
	    errmsg = "RPL language version declaration must be the first RPL statement"
	 elseif ast.pdecl.is(s) then
	    if a.block_pdecl then
	       errmsg = "Duplicate package declaration"
	    else
	       errmsg = "Package decl must precede imports and bindings"
	    end
	 end
	 table.insert(messages, violation.compile.new{who='loader',
						      message=errmsg,
						      ast=s})
	 return false
      end
   end -- for
   return true
end

local function compile(compiler, a, env, source_record, messages)
   -- The 'a' parameter is the AST to compile, which is a block that has been parsed, but not
   -- expanded yet.
   -- All dependencies of the block have been loaded.
   -- Bindings for all dependencies have been created already.
   -- The 'request' parameter is nil for direct user input, or a loadrequest that indicates why 
   -- we are compiling the code that produced 'a'.
   if not compiler.expand_block(a, env, messages) then return false; end
   -- One of the expansion steps is to fill in the pdecl and ideclist slots in the block AST, so
   -- we can now use those fields.
   local pkgname = a.block_pdecl and a.block_pdecl.name
   local request = source_record.origin
   if request and request.importpath and (not pkgname) then
      local msg = request.importpath .. " is not a module (no package declaration found)"
      table.insert(messages, violation.info.new{who='loader', message=msg, ast=a})
   end
   -- If we are compiling 'a' due to a request and the request has an importpath and a prefix,
   -- then those came from an import declaration.  The packagename in the request object was
   -- not known until now (because we just parsed and expanded the module source).
   if request and request.importpath then request.packagename = pkgname; end
   if not compiler.compile_block(a, env, request, messages) then
      common.note(string.format("load: failed to compile %s", pkgname or "<top level>"))
      return false
   end
   common.note(string.format("load: compiled %s", pkgname or "<top level>"))
   return true
end

local load_dependencies;

local function parse_block(compiler, source_record, messages)

   local t0
   if PROFILE then
      t0 = os.clock()
      profile_println("importing (parsing / parse_block) ", tostring(source_record.origin and source_record.origin.filename))
   end
   local a = compiler.parse_block(source_record, messages)
   if not a then return false; end		    -- errors will be in messages table
   if PROFILE then
      profile_println("parsing / parse_block time = ", time(t0), "ms")
      t0 = os.clock()
      profile_println("importing (parsing / validate_block) ", tostring(source_record.origin and source_record.origin.filename))
   end
   if not validate_block(a, messages) then return false; end
   if PROFILE then profile_println("parsing / validate_block time = ", time(t0), "ms"); end
   -- Via side effects, a.block_pdecl and a.block_ideclists are now filled in.
   return a
end

-- 'loadpkg.source' loads rpl source code.  That code, source, may or may not define a module.  If
-- source defines a module, i.e. it has a package declaration, then:
-- (1) the package will be instantiated (as an environment), and
-- (2) the info needed to create a binding for that package will be returned.
function loadpkg.source(compiler, pkgtable, top_level_env, searchpath, source, origin, messages)
   assert(type(compiler)=="table")
   assert(type(pkgtable)=="table")
   assert(environment.is(top_level_env))
   assert(type(searchpath)=="string")
   assert(type(source)=="string")
   assert(origin==nil or common.loadrequest.is(origin))
   assert(type(messages)=="table")
   -- loadpkg.source() is used to:
   -- (1) load user input, in which case the origin argument is nil, or
   -- (2) load code from a file named by the user, in which case:
   --     (a) origin.importpath == nil, and
   --     (b) origin.filename ~= nil
   if origin then assert(origin.importpath==nil); assert(origin.filename); end
   local source_record = common.source.new{text=source,
					   origin=origin,
					   }
   local a = parse_block(compiler, source_record, messages)
   if not a then return false; end		    -- errors will be in messages table
   local env
   if a.block_pdecl then
      assert(a.block_pdecl.name)
      local _, prelude = common.pkgtableref(pkgtable, environment.PRELUDE_IMPORTPATH, nil)
      assert(prelude)
      env = environment.new(prelude)
      env.origin = origin
   else
      env = environment.extend(top_level_env)
   end
   if not load_dependencies(compiler, pkgtable, searchpath, source_record, a, env, {}, messages) then
      return false
   end
   if not compile(compiler, a, env, source_record, messages) then
      return false
   end
   if a.block_pdecl then
      -- The code we compiled defined a module, which we have instantiated as a package (in env).
      -- But there is no importpath, so we cannot create an entry in the package table.
      return true, a.block_pdecl.name, env
   else
      -- The caller must replace their top_level_env with the returned env in order to see the new
      -- bindings. 
      return true, nil, env
   end
end

local function import_from_source(compiler, pkgtable, searchpath, source_record, loadinglist, messages)
   local t0
   if PROFILE then
      profile_println("importing (parsing) ", tostring(source_record.origin and source_record.origin.filename))
      t0 = os.clock()
   end
   local src = source_record.text
   local origin = source_record.origin
   local a = parse_block(compiler, source_record, messages)
   if PROFILE then
      profile_println("time = ", time(t0), "ms")
      profile_println("importing (dependencies) ", tostring(source_record.origin and source_record.origin.filename))
      t0 = os.clock()
   end
   if not a then return false; end		    -- errors will be in messages table
   if not a.block_pdecl then
      local msg = "imported code is not a module"
      table.insert(messages, violation.compile.new{who='loader', message=msg, ast=source_record})
      return false
   end
   origin.packagename = a.block_pdecl.name
   local _, prelude = common.pkgtableref(pkgtable, environment.PRELUDE_IMPORTPATH, nil)
   assert(prelude)
   local env = environment.new(prelude)
   env.origin = origin
   if not load_dependencies(compiler, pkgtable, searchpath, source_record, a, env, loadinglist, messages) then
      return false
   end
   if PROFILE then
      profile_println("time = ", time(t0), "ms")
      profile_println("importing (compiling) ", tostring(source_record.origin and source_record.origin.filename))
      t0 = os.clock()
   end
   if not compile(compiler, a, env, source_record, messages) then
      return false
   end
   if PROFILE then
      profile_println("time = ", time(t0), "ms")
   end
   common.pkgtableset(pkgtable, origin.importpath, origin.prefix, origin.packagename, env)
   return true, origin.packagename, env
end

local function find_module_source(compiler, pkgtable, searchpath, source_record, loadinglist, messages)
   local fullpath, src, msg = common.get_file(source_record.origin.importpath, searchpath)
   if src then
      -- Check to see if fullpath is in the list of "things that are being loaded now",
      -- and if so, signal an error that there are circular dependencies
      if not loadinglist[fullpath] then
	 loadinglist[fullpath] = true
	 return src, fullpath
      else
	 msg = "Detected circular list of module dependencies"
	 --for k,_ in pairs(loadinglist) do msg = msg .. "\n" .. k; end
      end
   end
   table.insert(messages, violation.compile.new{who='loader', message=msg, ast=source_record})
   return false
end

local function create_package_bindings(prefix, pkgenv, target_env)
   assert(type(prefix)=="string")
   assert(environment.is(pkgenv))
   assert(environment.is(target_env))
   if prefix=="." then
      -- import all exported bindings into the target environment
      for name, obj in pkgenv:bindings() do
	 assert(type(obj)=="table", name .. " bound to " .. tostring(obj))
	 if obj.exported then			    -- quack
	    if target_env:lookup(name) then
	       common.note("load: rebinding ", name)
	    else
	       common.note("load: binding ", name)
	    end
	    target_env:bind(name, obj)
	 end
      end -- for each binding in the package
   else
      -- import the entire package under the desired prefix
      if target_env:lookup(prefix) then
	 common.note("load: rebinding ", prefix)
      end
      target_env:bind(prefix, pkgenv)
      common.note("load: binding package prefix " .. prefix)
   end
end

local function import_builtin(importpath)
   local pkgname, env = builtins.get_package(importpath)
   if pkgname then 
      return true, pkgname, env
   end
   return false
end

local function import_one_force(compiler, pkgtable, searchpath, source_record, loadinglist, messages)
   local origin = assert(source_record.origin)
   common.note("load: looking for ", origin.importpath)
   -- FUTURE: Next, look for a compiled version of the file to load
   -- Finally, look for a source file to compile and load
   local src, fullpath = find_module_source(compiler, pkgtable, searchpath, source_record, loadinglist, messages)
   if not src then return false; end 		    -- message already in 'messages'
   if builtins.is_builtin_package(origin.importpath, fullpath) then
      common.note("load: loading ", origin.importpath, ", a built-in package")
      return import_builtin(origin.importpath)
   end
   common.note("load: loading ", origin.importpath, " from ", fullpath)
   local sref = common.source.new{text=src,
				  origin=common.loadrequest.new{importpath=origin.importpath,
								prefix=origin.prefix,
								packagename=nil,
								filename=fullpath},
			          parent=source_record}
   return import_from_source(compiler, pkgtable, searchpath, sref, loadinglist, messages)
end

local function import_one(compiler, pkgtable, searchpath, source_record, loadinglist, messages)
   local origin = assert(source_record.origin)
   -- First, look in the pkgtable to see if this pkg has been loaded already
   local pkgname, pkgenv = common.pkgtableref(pkgtable, origin.importpath, origin.prefix)
   if pkgname then
      common.note("load: ", origin.importpath, " already loaded")
      return true, pkgname, pkgenv
   end
   return import_one_force(compiler, pkgtable, searchpath, source_record, loadinglist, messages)
end

function loadpkg.import(compiler, pkgtable, searchpath, packagename, as_name, env, messages)
   assert(type(compiler)=="table")
   assert(type(pkgtable)=="table")
   assert(type(searchpath)=="string")
   assert(type(packagename)=="string")
   assert(as_name==nil or type(as_name)=="string")
   assert(environment.is(env))
   assert(type(messages)=="table")
   local origin = common.loadrequest.new{importpath=packagename, prefix=as_name}
   local source_record = common.source.new{origin=origin}
   local ok, pkgname, pkgenv = import_one_force(compiler, pkgtable, searchpath, source_record, {}, messages)
   if not ok then return false; end 		    -- message already in 'messages'
   create_package_bindings(origin.prefix or pkgname, pkgenv, env)
   return true, pkgname
end

-- load_dependencies recursively loads each import in ideclist.
-- Returns success; side-effects the messages argument.
function load_dependencies(compiler, pkgtable, searchpath, source_record, a, target_env, loadinglist, messages)
   assert(type(compiler)=="table")
   assert(type(pkgtable)=="table")
   assert(type(searchpath)=="string")
   assert(common.source.is(source_record))
   assert(ast.block.is(a))
   assert(environment.is(target_env))
   assert(type(messages)=="table")
   assert(a.block_ideclists==nil or (type(a.block_ideclists)=="table"),
	  "a.block_ideclists is: "..tostring(a.block_ideclists))
   for _, ideclist in ipairs(a.block_ideclists or {}) do
      assert(ast.ideclist.is(ideclist))
      local idecls = ideclist.idecls
      for _, decl in ipairs(idecls) do
	 assert(decl.sourceref)
	 local sref = common.source.new{text=source_record.text,
					origin=common.loadrequest.new{importpath=decl.importpath,
								      prefix=decl.prefix},
					parent=common.source.new{text=decl.sourceref.text,
								 s=decl.sourceref.s,
								 e=decl.sourceref.e,
								 origin=source_record.origin,
								 parent=source_record}}
	 local ok, pkgname, pkgenv = import_one(compiler, pkgtable, searchpath, sref, loadinglist, messages)
	 if not ok then
	    common.note("FAILED to import from path " .. tostring(decl.importpath))
	    local err = violation.compile.new{who="loader",
					      message="failed to load " .. tostring(decl.importpath),
					      ast=source_record}
	    table.insert(messages, err)
	    return false
	 end
      end
      -- With all imports loaded and registered in pkgtable, we can now create bindings in target_env
      -- to make the exported bindings accessible.
      for _, decl in ipairs(idecls) do
	 local pkgname, pkgenv = common.pkgtableref(pkgtable, decl.importpath, decl.prefix)
	 local prefix = decl.prefix or pkgname
	 assert(type(prefix)=="string")
	 create_package_bindings(prefix, pkgenv, target_env)
      end
   end -- for each ideclist in a.block_ideclists
   return true
end

return loadpkg
