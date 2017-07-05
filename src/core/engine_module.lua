---- -*- Mode: Lua; -*-                                                                           
----
---- engine.lua    The RPL matching engine
----
---- © Copyright IBM Corporation 2016, 2017.
---- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
---- AUTHOR: Jamie A. Jennings

-- TODO: a Lua-module-aware version of strict.lua that works with _ENV and not _G
-- require "strict"

-- The two principle use case categories for Rosie may be characterized as Interactive and
-- Production, where the latter includes big data scenarios in which performance is paramount and
-- functions like compiling, tracing, and generating human-readable output are not needed.
-- Support for matching using compiled patterns is the focus of "Production" use.

----------------------------------------------------------------------------------------
-- Engine
----------------------------------------------------------------------------------------
-- A matching engine is a stateful Lua object instantiated in order to match patterns
-- against input data.  An engine is the primary abstraction for using Rosie
-- programmatically in Lua.  (Recall that the REPL, CLI, and API are written in Lua.)
--
-- The engine functions never raise an error when properly called, unless there's an internal
-- rosie bug of course.  The Rosie C API calls these functions properly, as does the CLI and
-- REPL.  Interactive use of these functions by Lua programmers may trigger engine_error.
-- 
-- engine.new(optional_name) creates a new engine with only a "base" environment
--   returns id which is a string;
-- e:name() returns the engine name (a string) or nil if not set
-- e:id() returns the engine id, a string that uniquely identifies the engine within the Lua state
--   in which it was created.
--
-- e:load(rpl_string) compiles rpl_string in the current engine environment
--   the rpl_string has "file semantics", i.e. it can be a module.
--   returns success code and a list of violation objects
-- 
-- e:compile(expression, flavor) compiles the rpl expression
--   returns an rplx object or nil, and a list of violation objects
--   API only: instead of the rplx object, returns the (string) id of an rplx object with
--   indefinite extent; 
--   The flavor argument, if nil or "match" compiles expression unmodified.  Otherwise:
--     flavor=="search" compiles {{!expression .}* expression}+
--     and more flavors can be added later, e.g.
--     flavor==n, for integer n, compiles {{!expression .}* expression}{0,n}
--   The flavor feature is a convenience function that is a stopgap until we have macros/functions 
--
-- r:match(input, optional_start) like e:match but r is a compiled rplx object
--   returns match or nil, and leftover
--
-- e:match(expression, input, optional_start, optional_flavor, optional_acc0, optional_acc1)
--   behaves like: r=e:compile(expression, optional_flavor);
--                 r:match(input, optional_start, optional_acc0, optional_acc1)
--   optional_acc0 is an integer accumulator of total match time
--   optional_acc1 is an integer accumulator of match time spent in the lpeg vm
-- ???  API only: expression can be an rplx id, in which case that compiled expression is used
--   returns ok, match or nil, leftover, time
--      where ok means "successful compile", and if not ok then match is a table of messages
-- 
-- e:tracematch(expression, input, optional_start, optional_flavor) like match, with tracing (was eval)
-- ??? API only: expression can be an rplx id, in which case that compiled expression is used
--   returns match or nil, leftover, trace (a json object or a string, depending on output encoding);
-- 
-- e:output(optional_formatter) sets or returns the formatter (a function)
--   an engine calls formatter on each successful match result;
--
-- e:lookup(optional_identifier) returns the definition of optional_identifier or the entire environment
--
-- e:clear(optional_identifier) erases the definition of optional_identifier or the entire environment
-- 

-- FUTURE:
--
-- e:trace(id1, ... | nil) trace the listed identifiers, or if nil return the identifiers being traced
-- e:traceall(flag) trace all identifiers if flag is true, or no indentifiers if flag is false
-- e:untrace(id1, ...) untrace the listed identifiers
-- e:tracesearch(identifier, input, optional_start) like search, but generates a trace output (was eval)
--
-- e:stats() returns number of patterns bound, some measure of env size (via lua collectgarbage), more...


local engine_module = {}

local string = require "string"
local io = require "io"

local lpeg = require "lpeg"
local recordtype = require "recordtype"
local common = require "common"
local rmatch = common.rmatch
local pfunction = common.pfunction
local macro = common.macro
local environment = require "environment"
local lookup = environment.lookup
local bind = environment.bind
local violation = require "violation"
local writer = require "writer"
--local eval = require "eval"

local rplx 					    -- forward reference
local engine_error				    -- forward reference

----------------------------------------------------------------------------------------

-- Grep searches a line for all occurrences of a given pattern.  For Rosie to search a line for
-- all occurrences of pattern p, we want to transform p into:  {{!p .}* p}+
-- E.g.
--    bash-3.2$ ./run '{{!int .}* int}+' /etc/resolv.conf 
--    10 0 1 1 
--    2606 000 1120 8152 2 7 6 4 1 
--
-- Flavors are RPL "macros" hand-coded in Lua, used in Rosie v1.0 as a very limited kind of macro
-- system that we can extend in versions 1.x without losing backwards compatibility (and without
-- introducing a "real" macro facility.
-- N.B. Macros are transformations on ASTs, so they leverage the (rough and in need of
-- refactoring) syntax module.

local function compile_search(en, pattern_exp)
   local parse = en.compiler.parser.parse_expression
   local compile = en.compiler.compile_expression
   local env = environment.extend(en._env)	    -- new scope, which will be discarded
   -- First, we compile the exp in order to give an accurate message if it fails
   -- What to do with leftover?
   local warnings = {}
   local ast, orig_ast, leftover = parse(pattern_exp, nil, warnings)
   if not ast and ast.subs then return false, warnings, leftover; end
   local pat, msgs = compile(nil, ast, en._pkgtable, env)
   if not pat then return false, msgs; end
   local replacement = ast.subs[1]
   -- Next, transform pat.ast
   local ast, orig_ast, leftover = parse("{{!e .}* e}+", nil, warnings)
   assert(type(ast)=="table" and ast.subs and ast.subs[1] and (not ast.subs[2]))
   assert(ast.type=="rpl_expression")
   assert(ast.subs[1].type=="raw_exp", "type is: " .. ast.subs[1].type)
   ast = ast.subs[1]
   assert(ast.subs and ast.subs[1])
   local template = ast.subs[1]
   local grep_ast = syntax.replace_ref(template, "e", replacement)
   assert(type(grep_ast)=="table", "syntax.replace_ref failed")
   grep_ast = common.create_match("rpl_expression", 1, "search:(" .. pattern_exp .. ")", grep_ast)
   return compile(nil, grep_ast, en._pkgtable, env)
end

local function compile_match(en, source)
   local parse = en.compiler.parser.parse_expression
   local compile = en.compiler.compile_expression
   local messages = {}
   local ast, original_ast, leftover = parse(source, nil, messages)
   assert(type(messages)=="table")
   if not ast then return false, messages; end
   return compile(nil, ast, en._pkgtable, en._env)
end

local function engine_compile(en, expression, flavor)
   flavor = flavor or "match"
   if type(expression)~="string" then engine_error(en, "Expression not a string: " .. tostring(expression)); end
   if type(flavor)~="string" then engine_error(en, "Flavor not a string: " .. tostring(flavor)); end
   local pat, msgs
   if flavor=="match" then
      pat, msgs = compile_match(en, expression)
   elseif flavor=="search" then
      pat, msgs = compile_search(en, expression)
   else
      engine_error(en, "Unknown flavor: " .. flavor)
   end
   if not pat then return false, msgs; end
   return rplx.new(en, pat), msgs
end

-- N.B. The _engine_match code is essentially duplicated (for speed, to avoid a function call) in
-- process_input_file (below).  There's still room for optimizations, e.g.
--   Create a closure over the encode function to avoid looking it up in e.
--   Close over lpeg.match to avoid looking it up via the peg.
--   Close over the peg itself to avoid looking it up in pat.
local function _engine_match(e, pat, input, start, total_time_accum, lpegvm_time_accum)
   local result, nextpos
   local encode = e.encode_function
   result, nextpos, total_time_accum, lpegvm_time_accum =
      rmatch(pat.peg,
	     input,
	     start,
	     type(encode)=="number" and encode,
	     total_time_accum,
	     lpegvm_time_accum)
   if result then
      return (type(encode)=="function") and encode(result) or result,
             #input - nextpos + 1, 
             total_time_accum, 
             lpegvm_time_accum
   end
   -- return: no match, leftover chars, t0, t1
   return false, #input, total_time_accum, lpegvm_time_accum;
end

-- FUTURE: Maybe cache expressions?
-- returns matches, leftover, total match time, total spent in lpeg vm
local function make_matcher(processing_fcn)
   return function(e, expression, input, start, flavor, total_time_accum, lpegvm_time_accum)
	     if type(input)~="string" then engine_error(e, "Input not a string: " .. tostring(input)); end
	     if start and type(start)~="number" then engine_error(e, "Start position not a number: " .. tostring(start)); end
	     if flavor and type(flavor)~="string" then engine_error(e, "Flavor not a string: " .. tostring(flavor)); end
	     if rplx.is(expression) then
		return true, processing_fcn(e, expression._pattern, input, start, total_time_accum, lpegvm_time_accum)
	     elseif type(expression)=="string" then -- expression has not been compiled
		-- If we cache, look up expression in the cache here.
		local r, msgs = e:compile(expression, flavor)
		if not r then return false, msgs; end
		return true, processing_fcn(e, r._pattern, input, start, total_time_accum, lpegvm_time_accum)
	     else
		engine_error(e, "Expression not a string or rplx object: " .. tostring(expression));
	     end
	  end  -- matcher function
end

-- returns matches, leftover
local engine_match = make_matcher(_engine_match)

-- returns matches, leftover, trace
local engine_tracematch = make_matcher(function(e, pat, input, start)
				    local m, left, ttime, lptime = _engine_match(e, pat, input, start)
				    local _,_,trace, ttime, lptime = eval.eval(pat, input, start, e, false)
				    return m, left, trace, ttime, lptime
				 end)

----------------------------------------------------------------------------------------

local maybe_load_dependency			    -- forward reference
local load_dependencies				    -- forward reference
local import_dependency				    -- forward reference

-- load a unit of rpl code (decls and statements) into an environment:
--   * parse out the dependencies (import decls)
--   * load dependencies that have not been loaded (into the pkgtable)
--   * import the dependencies into the target environment
--   * compile the input in the target environment
--   * return success code, modname or nil, table of messages (errors, warnings)

local function load_input(e, target_env, input, importpath, modonly)
   assert(engine.is(e))
   assert(environment.is(target_env), "target not an environment: " .. tostring(target_env))
   assert(type(e.searchpath)=="string", "engine search path not a string")
   local messages = {}
   local parser = e.compiler.parser
   local ast, original_ast, leftover
   local warnings = {}
   if type(input)=="string" then
      ast, original_ast, leftover = parser.parse_statements(input, nil, warnings)
   elseif type(input)=="table" then
      ast, original_ast, leftover = input, input, 0
   else
      engine_error(e, "Error: input not a string or ast: " .. tostring(input));
   end
   assert(type(warnings)=="table")
   if not ast then
      return false,
	 nil,
	 {violation.syntax.new{who='engine load input',
			       message=table.concat(warnings, "\n"),
			       origin=importpath,
			       src=(type(input)=="string" and input) or nil}}
   end
   table.move(warnings, 1, #warnings, #messages+1, messages)
   assert(type(ast)=="table")
   -- load_dependencies has side-effects on e._pkgtable, target_env, and messages
   if not load_dependencies(e, ast, target_env, messages, importpath) then
      return false, nil, messages
   end
   -- now we can compile the input
   local success, modname, more_messages = e.compiler.load(importpath, ast, e._pkgtable, target_env)
   assert(type(more_messages)=="table", "messages is: " .. tostring(more_messages))
   table.move(more_messages, 1, #more_messages, #messages+1, messages)
   if not success then
      common.note(string.format("FAILED TO COMPILE %s", modname))
      return false, modname, messages
   end
   if modonly and (not modname) then
      local msg = (importpath or "<top level>") .. " is not a module (no package declaration found)"
      table.insert(messages, violation.compile.new{who='load module', message=msg, ast=ast})
      return false, modname, msg, messages
   end
   common.note(string.format("COMPILED %s", modname or "<top level>"))
   return true, modname, messages
end

load_dependencies =
   function(e, ast, target_env, messages, importpath)
      local deps = e.compiler.parser.parse_deps(e.compiler.parser, ast)
      if not deps then return true; end
      for _, dep in ipairs(deps) do
	 local ok, modname, new_messages = maybe_load_dependency(e, ast, target_env, dep, importpath);
	 table.move(new_messages, 1, #new_messages, #messages+1, messages)
	 if not ok then return false; end
      end
      -- if all dependecies loaded ok, we can import them
      for _, dep in ipairs(deps) do import_dependency(e, target_env, dep); end
      return true
end
      
-- find and load any missing dependency
maybe_load_dependency =
   function(e, ast, target_env, dep, importpath)
      local messages = {}
      common.note("-> Loading dependency " .. dep.importpath .. " required by " .. (importpath or "<top level>"))
      local modname, modenv = e:pkgtableref(dep.importpath)
      if not modname then
	 common.note("Looking for ", dep.importpath, " required by ", (importpath or "<top level>"))
	 local fullpath, source = common.get_file(dep.importpath, e.searchpath)
	 if not fullpath then
	    local err = "cannot find module '" .. dep.importpath ..
	       "' needed by module '" .. (importpath or "<top level>") .. "'"
	    engine_error(e, err)
	 else
	    common.note("Loading ", dep.importpath, " from ", fullpath)
	    target_env = environment.new()
	    -- mutually recursive call to load_input, but now we can require that load_input
	    -- accept only modules, not any file of rpl code.
	    local ok, modname, new_messages = load_input(e, target_env, source, dep.importpath, true)
	    table.move(new_messages, 1, #new_messages, #messages+1, messages)
	    if not ok then return false, modname, messages; end
	 end -- if not fullpath
      end -- if dependency was not already loaded
      return true, modname, messages
   end

import_dependency =
   function(e, target_env, dep)
      assert(engine.is(e))
      assert(environment.is(target_env))
      local modname, modenv = e:pkgtableref(dep.importpath)
      if dep.prefix=="." then
	 -- import all exported bindings into the current environment
	 for name, obj in modenv:bindings() do
	    if obj.exported then		    -- quack
	       if lookup(target_env, name) then
		  common.note("REBINDING ", name)
	       end
	       bind(target_env, name, obj)
	    end
	 end -- for each obj in the module environment
      else
	 -- import the entire package under the desired name
	 local packagename = dep.prefix or modname
	 if lookup(target_env, packagename) then
	    common.note("REBINDING ", packagename)
	 end
	 bind(target_env, packagename, modenv)
	 common.note("-> Binding module prefix: " .. packagename)
      end
   end

local function get_file_contents(e, filename, nosearch)
   if nosearch or util.absolutepath(filename) then
      local data, msg = util.readfile(filename)
      return filename, data, msg		    -- data could be nil
   else
      return common.get_file(filename, e.searchpath, "")
   end
end

local function load_file(e, filename, nosearch)
   if type(filename)~="string" then
      engine_error(e, "file name argument not a string: " .. tostring(filename))
   end
   local actual_path, source, msg = get_file_contents(e, filename, nosearch)
   if not source then return false, nil, msg, actual_path; end
   local success, modname, warnings = e.load(e, source, filename)
   return success, modname, warnings, actual_path
end

----------------------------------------------------------------------------------------

local function reconstitute_pattern_definition(id, p)
   if p then
      if recordtype.parent(p.ast) then
	 -- We have an ast, not a parse tree
	 return ast.tostring(p.ast) or "built-in RPL pattern"
      end
      return ( (p.original_ast and writer.reveal_ast(p.original_ast)) or
	    (p.ast and writer.reveal_ast(p.ast)) or
	 "// built-in RPL pattern //" )
   end
   engine_error(e, "undefined identifier: " .. id)
end

-- FUTURE: Update this to make a use general pretty printer for the contents of the environment.
local function properties(name, obj)
   if common.pattern.is(obj) then
      local kind = "pattern"
      local capture = (not obj.alias)
      local color = (co and co.colormap and co.colormap[item]) or ""
      local binding = reconstitute_pattern_definition(name, obj)
      return {type=kind, capture=capture, color=color, binding=binding}
   elseif environment.is(obj) then
      return {type="package", color="", binding="<not printable>"}
   elseif pfunction.is(obj) then
      return {type="function", color="", binding="<not printable>"}
   elseif macro.is(obj) then
      return {type="macro", color="", binding="<not printable>"}
   else
      error("Internal error: unknown kind of object in environment, stored at " ..
	    tostring(name) .. ": " .. tostring(obj))
   end
end

local function parse_identifier(en, str)
   local msgs = {}
   local m = en.compiler.parser.parse_expression(str, nil, msgs)
   if ast.ref.is(m) then
      -- using the new parser
      return m.localname, m.packagename
   end
   if m and m.subs and m.subs[1] then
      assert(m.type=="rpl_expression")
      m = m.subs[1]
      if m.type=="ref" then
	 return m.text, nil
      elseif m.type=="extref" then
	 assert(m.subs and m.subs[1] and m.subs[2])
	 assert(m.subs[1].type=="packagename")
	 assert(m.subs[2].type=="localname")
	 return m.subs[2].text, m.subs[1].text
      end -- is there a packagename in the identifier?
   end -- did we get an identifier?
end
	    
-- Lookup an identifier in the engine's environment, and get a human-readable definition of it
-- (reconstituted from its ast).  If identifier is null, return the entire environment.
local function get_environment(en, identifier)
   if identifier then
      local localname, prefix = parse_identifier(en, identifier)
      local val = lookup(en._env, localname, prefix)
      return val and properties(identifier, val)
   end
   local flat_env = environment.flatten(en._env)
   -- Rewrite the flat_env table, replacing the pattern with a table of properties
   for id, pat in pairs(flat_env) do flat_env[id] = properties(id, pat); end
   return flat_env
end

local function clear_environment(en, identifier)
   if identifier then
      if lookup(en._env, identifier) then bind(en._env, identifier, nil); return true
      else return false; end
   else -- no identifier arg supplied, so wipe the entire env
      en._env = environment.new()
      return true
   end
end

-- Built-in encoder options:
-- false = return lua table as usual
-- -1 = no output
--  0 = compact byte encoding with only start/end indices (no text)
--  1 = compact json encoding with only start/end indices (no text)
local function get_set_encoder_function(en, f)
   if f==nil then return en.encode_function; end
   if f==false or type(f)=="number" or type(f)=="function" then
      en.encode_function = f;
   else engine_error(en, "Invalid output encoder: " .. tostring(f)); end
end

---------------------------------------------------------------------------------------------------

local default_compiler = false

local function set_default_compiler(compiler)
   default_compiler = compiler
end

local function get_default_compiler()
   return default_compiler
end

local default_searchpath = false

local function set_default_searchpath(str)
   default_searchpath = str
end

local function get_default_searchpath()
   return default_searchpath
end

engine_module.post_create_hook = function(e, ...) end

---------------------------------------------------------------------------------------------------

local process_input_file = {}

local function open3(e, infilename, outfilename, errfilename)
   if type(infilename)~="string" then e:_error("bad input file name"); end
   if type(outfilename)~="string" then e:_error("bad output file name"); end
   if type(errfilename)~="string" then e:_error("bad error file name"); end   
   local infile, outfile, errfile, msg
   if #infilename==0 then infile = io.stdin;
   else infile, msg = io.open(infilename, "r"); if not infile then e:_error(msg); end; end
   if #outfilename==0 then outfile = io.stdout
   else outfile, msg = io.open(outfilename, "w"); if not outfile then e:_error(msg); end; end
   if #errfilename==0 then errfile = io.stderr;
   else errfile, msg = io.open(errfilename, "w"); if not errfile then e:_error(msg); end; end
   return infile, outfile, errfile
end

local function engine_process_file(e, expression, flavor, trace_flag, infilename, outfilename, errfilename, wholefileflag)
   if type(trace_flag)~="boolean" then e:_error("bad trace flag"); end
   --
   -- Set up pattern to match.  Always compile it first, even if we are going to call tracematch later.
   -- This is so that we report errors uniformly at this point in the process, instead of after
   -- opening the files.
   --
   local r, msgs
   if engine_module.rplx.is(expression) then
      r = expression
   else
      r, msgs = e:compile(expression, flavor)
      if not r then e:_error(table.concat(msgs, '\n')); end
   end
   assert(engine_module.rplx.is(r))

   -- This set of simple optimizations almost doubles performance of the loop through the file
   -- (below) in typical cases, e.g. syslog pattern. 
   local encoder = e.encode_function		    -- optimization
   local built_in_encoder = type(encoder)=="number" and encoder
   if built_in_encoder then encoder = false; end
   local peg = r._pattern.peg			    -- optimization
   local matcher = function(input, start)
		      return rmatch(peg, input, start, built_in_encoder)
		   end                              -- TODO: inline this for performance

   local infile, outfile, errfile = open3(e, infilename, outfilename, errfilename);
   local inlines, outlines, errlines = 0, 0, 0;
   local nextline
   if wholefileflag then
      nextline = function()
		    if wholefileflag then
		       wholefileflag = false;
		       return infile:read("a")
		    end
		 end
   else
      nextline = infile:lines();
   end
   local o_write, e_write = outfile.write, errfile.write
   local ok, l = pcall(nextline);
   if not ok then e:_error(l); end
   local _, m, leftover, trace
   while l do
      if trace_flag then _, _, trace = e:tracematch(expression, l); end
      m, nextpos = matcher(l);		    -- this is nextpos, NOT leftover
      -- What to do with leftover?  User might want to see it.
      -- local leftover = (#input - nextpos + 1);
      if trace then o_write(outfile, trace, "\n"); end
      if m then
	 if type(m)=="userdata" then
	    lpeg.writedata(outfile, m)
	 else
	    local str = encoder and encoder(m) or m
	    o_write(outfile, str);
	 end
	 o_write(outfile, "\n")
	 outlines = outlines + 1
      else
	 e_write(errfile, l, "\n")
	 errlines = errlines + 1
      end
      if trace then o_write(outfile, "\n"); end
      inlines = inlines + 1
      l = nextline(); 
   end -- while
   infile:close(); outfile:close(); errfile:close();
   return inlines, outlines, errlines
end

function process_input_file.match(e, expression, flavor, infilename, outfilename, errfilename, wholefileflag)
   return engine_process_file(e, expression, flavor, false, infilename, outfilename, errfilename, wholefileflag)
end

function process_input_file.tracematch(e, expression, flavor, infilename, outfilename, errfilename, wholefileflag)
   return engine_process_file(e, expression, flavor, true, infilename, outfilename, errfilename, wholefileflag)
end

---------------------------------------------------------------------------------------------------

local function engine_create(name, compiler, searchpath)
   compiler = compiler or default_compiler
   searchpath = searchpath or default_searchpath
   if not compiler then error("no default compiler set"); end
   local new = engine.factory { name=function() return name; end,
			     compiler=compiler,
			     searchpath=searchpath,
			     _env=environment.new(),
			     _pkgtable=environment.make_module_table(),
		    }
   engine_module.post_create_hook(new)
   return new
end

function engine_error(e, msg)
   error(string.format("Engine %s: %s\n%s", tostring(e), tostring(msg),
   		       ROSIE_DEV and (debug.traceback().."\n") or "" ), 0)
end

local engine = 
   recordtype.new("engine",
		  {  name=function() return nil; end, -- for reference, debugging
		     compiler=false,
		     _env=false,
		     _pkgtable=false,
		     _error=engine_error,

		     id=recordtype.id,

		     pkgtableref=function(self, path)
				    return common.pkgtableref(self._pkgtable, path)
				 end,
		     pkgtableset=function(self, path, p, e)
				    common.pkgtableset(self._pkgtable, path, nil, p, e)
				 end,

		     encode_function=false,	      -- false or nil ==> use default encoder
		     output=get_set_encoder_function,

		     lookup=get_environment,
		     clear=clear_environment,

		     load=function(e, input)
			     return load_input(e, e._env, input)
			  end,
		     loadfile=load_file,
		     import=function() error("'import' unsupported for this engine"); end,
		     compile=engine_compile,
		     dependencies=function() error("'dependencies' unsupported for this engine"); end,
		     searchpath="",

		     match=engine_match,
		     tracematch=engine_tracematch,

		     matchfile = process_input_file.match,
		     tracematchfile = process_input_file.tracematch,

		  },
		  engine_create
	       )

----------------------------------------------------------------------------------------

local rplx_create = function(en, pattern)			    
		       return rplx.factory{ _engine=en,
					    _pattern=pattern,
					    match=function(self, ...)
						     return _engine_match(en, pattern, ...)
						  end }; end

rplx = recordtype.new("rplx",
		      { _pattern=recordtype.NIL;
			_engine=recordtype.NIL;
			--
			match=false;
			trace=false;
		      },
		      rplx_create
		   )

---------------------------------------------------------------------------------------------------

engine_module.engine = engine
engine_module._set_default_compiler = set_default_compiler
engine_module._set_default_searchpath = set_default_searchpath
engine_module._get_default_compiler = get_default_compiler
engine_module._get_default_searchpath = get_default_searchpath
engine_module.rplx = rplx

return engine_module
