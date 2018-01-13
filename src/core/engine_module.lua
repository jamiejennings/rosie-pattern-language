---- -*- Mode: Lua; -*-                                                                           
----
---- engine.lua    The RPL matching engine
----
---- © Copyright IBM Corporation 2016, 2017.
---- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
---- AUTHOR: Jamie A. Jennings

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
-- e:compile(expression) compiles the rpl expression
--   returns an rplx object or nil, and a list of violation objects
--   API only: instead of the rplx object, returns the (string) id of an rplx object with
--   indefinite extent; 
--
-- r:match(input, optional_start) like e:match but r is a compiled rplx object
--   returns match or nil, and leftover
--
-- r:trace(input, optional_start) like e:trace but r is a compiled rplx object
--   returns a trace object
--
-- e:match(expression, input, optional_start, optional_acc0, optional_acc1)
--   behaves like: r=e:compile(expression);
--                 r:match(input, optional_start, optional_acc0, optional_acc1)
--   optional_start is an integer index into the input (defaults to 1, the first character)
--   optional_acc0 is an integer accumulator of total match time (defaults to 0)
--   optional_acc1 is an integer accumulator of match time spent in the lpeg vm (defaults to 0)
-- ???  API only: expression can be an rplx id, in which case that compiled expression is used
--   returns ok, match or nil, leftover, time
--      where ok means "successful compile", and if not ok then match is a table of messages
-- 
-- e:trace(expression, input, optional_start) like match, but generates a trace of the entire matching process
--   ??? API only: expression can be an rplx id, in which case that compiled expression is used
--   returns a trace object
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
-- e:traceid(id1, ... | nil) trace the listed identifiers, or if nil return the identifiers being traced
-- e:traceall(flag) trace all identifiers if flag is true, or no indentifiers if flag is false
-- e:untraceid(id1, ...) untrace the listed identifiers
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
local violation = require "violation"
local writer = require "writer"
local loadpkg = require "loadpkg"
local co = require "color"
local trace = require "trace"

local engine, rplx				    -- forward reference
local engine_error				    -- forward reference

----------------------------------------------------------------------------------------

local function compile_expression(e, input)
   local messages = {}
   local ast = input
   if type(input)=="string" then
      ast = e.compiler.parse_expression(common.source.new{text=input}, messages)
      -- Syntax and other errors will be in messages table
      if not ast then return false, messages; end
   end
   if not recordtype.parent(ast) then
      assert(false, "unexpected input type to compile_expression: " .. tostring(ast))
   end
   ast = e.compiler.expand_expression(ast, e.env, messages)
   -- Errors will be in messages table
   if not ast then return false, messages; end
   local pat = e.compiler.compile_expression(ast, e.env, messages)
   if not pat then return false, messages; end
   return rplx.new(e, pat), messages
end

local function really_load(e, source, origin)
   local messages = {}
   local ok, pkgname, env = loadpkg.source(e.compiler,
					   e.pkgtable,
					   e.env,
					   e.searchpath,
					   source,
					   origin,
					   messages)
   if ok then
      assert(environment.is(env))
      if pkgname then
	 -- We compiled a module, reified it as the package in 'env'
	 e.env:bind(pkgname, env)
      else
	 -- Did not load a module, so the env we passed in was extended with new bindings 
	 e.env = env
      end
   end
   return ok, pkgname, messages
end

local function load(e, input, fullpath)
   local origin = (fullpath and common.loadrequest.new{filename=fullpath}) or nil
   return really_load(e, input, origin)
end

-- Force a reloading of the imported package, as opposed to e:load('import foo') which will not
-- re-load a package that is already loaded.
local function import(e, packagename, as_name)
   local messages = {}
   local ok, pkgname = loadpkg.import(e.compiler,
			     e.pkgtable,
			     e.searchpath,
			     packagename,	    -- requested importpath
			     as_name,		    -- requested prefix
			     e.env,
			     messages)
   return ok, pkgname, messages
end

local function get_file_contents(e, filename, nosearch)
  if nosearch or util.absolutepath(filename) then
     local data, msg = util.readfile(filename)
     return filename, data, msg		    -- data could be nil
  else
     return common.get_file(filename, e.searchpath, "")
  end
end

local function loadfile(e, filename)
   if type(filename)~="string" then
      e.engine_error(e, "file name argument not a string: " .. tostring(filename))
   end
   local actual_path, source, errmsg = get_file_contents(e, filename, true)
   if not source then
      local err = violation.compile.new{who="loader",
					message=errmsg,
					ast=common.source.new{origin=
							      common.loadrequest.new{filename=actual_path}}}
      return false, nil, {err}
   end
   local ok, pkgname, messages = load(e, source, actual_path)
   return ok, pkgname, messages
end

----------------------------------------------------------------------------------------

-- N.B. The _match code is essentially duplicated (for speed, to avoid a function call) in
-- process_input_file (below).  There's still room for optimizations, e.g.
--   Create a closure over the encode function to avoid looking it up in e.
--   Close over lpeg.match to avoid looking it up via the peg.
--   Close over the peg itself to avoid looking it up in pat.
local function _match(rplx_exp, input, start, encoder, total_time_accum, lpegvm_time_accum)
   encoder = encoder or "default"
   local rmatch_encoder, fn_encoder = common.lookup_encoder(encoder)
   return rmatch(rplx_exp.pattern.peg,
		 input,
		 start,
		 rmatch_encoder,
		 fn_encoder,
		 total_time_accum,
		 lpegvm_time_accum)
end

local function _trace(r, input, start, style)
   return trace.expression(r, input, start, style)
end
   
-- Returns matches, leftover, total match time, total spent in lpeg vm
local function engine_match_trace(e, match_trace_fn, expression, input, start, encoder, total_time_accum, lpegvm_time_accum)
   local t = type(input)
   if (t ~= "userdata") and (t ~= "string") then
      engine_error(e, "Input not a buffer or string: " .. tostring(input))
   end
   start = start or 1
   if type(start)~="number" then engine_error(e, "Start position not a number: " .. tostring(start)); end
   local compiled_exp, msgs
   if type(expression)=="string" then
      -- Expression has not been compiled.
      compiled_exp, msgs = e:compile(expression)
      if not compiled_exp then return false, msgs; end
   elseif rplx.is(expression) then
      compiled_exp = expression
   else
      engine_error(e, "Expression not a string or rplx object: " .. tostring(expression));
   end
   return true, match_trace_fn(compiled_exp, input, start, encoder, total_time_accum, lpegvm_time_accum)
end

local function engine_match(e, expression, input, start, encoder, t0, t1)
   return engine_match_trace(e, _match, expression, input, start, encoder, t0, t1)
end

local function engine_trace(e, expression, input, start, style)
   return engine_match_trace(e, _trace, expression, input, start, style)
end

----------------------------------------------------------------------------------------

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
   if type(infilename)~="string" then return nil, tostring(infilename)
   elseif type(outfilename)~="string" then return nil, tostring(outfilename)
   elseif type(errfilename)~="string" then return nil, tostring(errfilename)
   end
   local infile, outfile, errfile, msg
   if #infilename==0 then infile = io.stdin;
   else
      infile, msg = io.open(infilename, "r");
      if not infile then return nil, infilename; end; end
   if #outfilename==0 then outfile = io.stdout
   else
      outfile, msg = io.open(outfilename, "w");
      if not outfile then return nil, outfilename; end; end
   if #errfilename==0 then errfile = io.stderr;
   else
      errfile, msg = io.open(errfilename, "w");
      if not errfile then return nil, errfilename; end; end
   return infile, outfile, errfile
end

local function engine_process_file(e, expression, op, infilename, outfilename, errfilename, encoder, wholefileflag)
   local r, msgs
   if engine_module.rplx.is(expression) then
      r = expression
   else
      r, msgs = e:compile(expression)
      if not r then e:error(table.concat(msgs, '\n')); end
      assert(engine_module.rplx.is(r))
   end
   local trace_flag = (op == "trace")
   local trace_style = encoder
   if trace_flag then encoder = "none"; end
   -- This set of simple optimizations almost doubles performance of the loop through the file
   -- (below) in cases where there are many lines to process.
   local rmatch_encoder, fn_encoder = common.lookup_encoder(encoder)
   local peg = r.pattern.peg			    -- optimization
   local matcher = function(input)
		      return rmatch(peg, input, 1, rmatch_encoder, fn_encoder)
		   end                              -- FUTURE: inline this for performance

   local infile, outfile, errfile = open3(e, infilename, outfilename, errfilename);
   if not infile then return nil, "No such file " .. tostring(outfile), nil; end
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
   local o_write_prim, e_write = outfile.write, errfile.write
   if common.encoder_returns_userdata(encoder) then
      o_write = function(handle, m)
		   lpeg.writedata(handle, m)
		   o_write_prim(handle, '\n')
		end
   else
      o_write = function(handle, m)
		   o_write_prim(handle, m, '\n')
		end
   end
   local ok, l = pcall(nextline);
   if not ok then e:error(l); end
   local _, m, leftover, trace_string
   local m, leftover
   while l do
      if trace_flag then _, _, trace_string = e:trace(expression, l, 1, trace_style); end
      m, leftover = matcher(l);		  -- What to do with leftover?  User might want to see it.
      if trace_string then o_write(outfile, trace_string, "\n"); end
      if m then
	 o_write(outfile, m);
	 outlines = outlines + 1
      else
	 e_write(errfile, l, "\n")
	 errlines = errlines + 1
      end
      if trace_string then o_write(outfile, "\n"); end
      inlines = inlines + 1
      l = nextline(); 
   end -- while
   infile:close(); outfile:close(); errfile:close();
   return inlines, outlines, errlines
end

function process_input_file.match(e, expression, infilename, outfilename, errfilename, encoder, wholefileflag)
   return engine_process_file(e, expression, "match", infilename, outfilename, errfilename, encoder, wholefileflag)
end

function process_input_file.trace(e, expression, infilename, outfilename, errfilename, trace_style, wholefileflag )
   return engine_process_file(e, expression, "trace", infilename, outfilename, errfilename, trace_style, wholefileflag)
end

---------------------------------------------------------------------------------------------------

local function create_engine(name, compiler, searchpath)
   compiler = compiler or default_compiler
   searchpath = searchpath or default_searchpath
   if not compiler then error("no default compiler set"); end
   local new_package_table = environment.new_package_table()
   local _, prelude = common.pkgtableref(new_package_table, environment.PRELUDE_IMPORTPATH, nil)
   assert(prelude)
   return engine.factory { name=function() return name; end,
			   compiler=compiler,
			   searchpath=searchpath,
			   env=environment.new(prelude),
			   pkgtable=new_package_table,
		        }
end

function engine_error(e, msg)
   error(string.format("Engine %s: %s\n%s", tostring(e), tostring(msg),
   		       ROSIE_DEV and (debug.traceback().."\n") or "" ), 0)
end

engine = 
   recordtype.new("engine",
		  {  name=function() return nil; end, -- for reference, debugging
		     compiler=false,
		     env=false,
		     pkgtable=false,
		     error=engine_error,

		     id=recordtype.id,

		     load=load,
		     loadfile=loadfile,
		     import=import,
		     set_libpath = function(self, newlibpath) self.searchpath = newlibpath; end,
		     searchpath="",

		     compile=compile_expression,
		     match=engine_match,
		     trace=engine_trace,

		     matchfile = process_input_file.match,
		     tracefile = process_input_file.trace,

		  },
		  create_engine
	       )

----------------------------------------------------------------------------------------

-- TODO: Since rplx is already compiled, arrange for rplx.match to call a streamlined version of
-- engine_match that does not need to check to see if the expression is a string and compile it.
local create_rplx = function(en, pattern)			    
		       return rplx.factory{ engine=en,
					    pattern=pattern,
					    match=function(self, input, start, encoder, t0, t1)
						     local ok, m, left, abend, t0, t1 =
							engine_match(en, self, input, start, encoder, t0, t1)
						     return m, left, abend, t0, t1
						  end,
					 };
		    end

rplx = recordtype.new("rplx",
		      { pattern=recordtype.NIL;
			engine=recordtype.NIL;
			--
			match=false;
			trace=false;
		      },
		      create_rplx
		   )

---------------------------------------------------------------------------------------------------

engine_module.engine = engine
engine_module.set_default_compiler = set_default_compiler
engine_module.set_default_searchpath = set_default_searchpath
engine_module.get_default_compiler = get_default_compiler
engine_module.get_default_searchpath = get_default_searchpath
engine_module.rplx = rplx

return engine_module
