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
local lookup = environment.lookup
local bind = environment.bind
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
      -- Syntax errors will be in messages table
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
   return rplx.new(e, pat)   
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
	 bind(e.env, pkgname, env)
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

local function import(e, packagename, as_name)
   local messages = {}
   local ok = loadpkg.import(e.compiler,
			     e.pkgtable,
			     e.searchpath,
			     packagename,	    -- requested importpath
			     as_name,		    -- requested prefix
			     e.env,
			     messages)
   return ok, messages
end

local function get_file_contents(e, filename, nosearch)
  if nosearch or util.absolutepath(filename) then
     local data, msg = util.readfile(filename)
     return filename, data, msg		    -- data could be nil
  else
     return common.get_file(filename, e.searchpath, "")
  end
end

-- FUTURE: re-work the return values?
local function loadfile(e, filename, nosearch)
   if type(filename)~="string" then
      e.engine_error(e, "file name argument not a string: " .. tostring(filename))
   end
   local actual_path, source, errmsg = get_file_contents(e, filename, nosearch)
   if not source then return false, nil, {errmsg}, actual_path; end
   local origin = common.loadrequest.new{filename=actual_path}
   local ok, pkgname, messages = really_load(e, source, origin)
   return ok, pkgname, messages, actual_path
end

----------------------------------------------------------------------------------------

-- N.B. The _match code is essentially duplicated (for speed, to avoid a function call) in
-- process_input_file (below).  There's still room for optimizations, e.g.
--   Create a closure over the encode function to avoid looking it up in e.
--   Close over lpeg.match to avoid looking it up via the peg.
--   Close over the peg itself to avoid looking it up in pat.
local function _match(rplx_exp, input, start, total_time_accum, lpegvm_time_accum)
   local result, nextpos
   local encode = rplx_exp.engine.encode_function
   result, nextpos, total_time_accum, lpegvm_time_accum =
      rmatch(rplx_exp.pattern.peg,
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

local function _trace(r, input, start)
   local tr = trace.expression(r, input, start)
   -- to string here, or more?
   return tr
end
   
-- FUTURE: Maybe cache expressions?
-- returns matches, leftover, total match time, total spent in lpeg vm
local function engine_match_trace(e, match_trace_fn, expression, input, start, total_time_accum, lpegvm_time_accum)
   if type(input)~="string" then engine_error(e, "Input not a string: " .. tostring(input)); end
   if start and type(start)~="number" then engine_error(e, "Start position not a number: " .. tostring(start)); end
   if type(expression)=="string" then
      -- Expression has not been compiled.
      -- If in future we cache the string expressions, then look up expression in the cache here.
      local msgs
      expression, msgs = e:compile(expression)
      if not expression then return false, msgs; end
   end
   if rplx.is(expression) then
      return true, match_trace_fn(expression, input, start, total_time_accum, lpegvm_time_accum)
   else
      engine_error(e, "Expression not a string or rplx object: " .. tostring(expression));
   end
end

local function engine_match(e, expression, input, start, t0, t1)
   return engine_match_trace(e, _match, expression, input, start, t0, t1)
end

local function engine_trace(e, expression, input, start)
   return engine_match_trace(e, _trace, expression, input, start)
end

----------------------------------------------------------------------------------------

local function reconstitute_pattern_definition(id, p)
   if p then
      if recordtype.parent(p.ast) then
	 -- We have an ast, not a parse tree
	 return ast.tostring(p.ast) or "built-in RPL pattern"
      end
      return (p.ast and writer.reveal_ast(p.ast)) or "// built-in RPL pattern //" 
   end
   engine_error(e, "undefined identifier: " .. id)
end

-- FUTURE: Update this to make a use general pretty printer for the contents of the environment.
local function properties(name, obj)
   if common.pattern.is(obj) then
      local kind = "pattern"
      local capture = (not obj.alias)
      local color, reason = co.query(name)
      local binding = reconstitute_pattern_definition(name, obj)
      local color_explanation = color
      if reason=="default" then color_explanation = color_explanation .. " (default)"; end
      return {type=kind, capture=capture, color=color_explanation, binding=binding}
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
   local m = en.compiler.parse_expression(common.source.new{text=str}, msgs)
   if ast.ref.is(m) then
      return m.localname, m.packagename
   end
   if m and m.subs and m.subs[1] then
      assert(m.type=="rpl_expression")
      m = m.subs[1]
      if m.type=="ref" then
	 return m.data, nil
      elseif m.type=="extref" then
	 assert(m.subs and m.subs[1] and m.subs[2])
	 assert(m.subs[1].type=="packagename")
	 assert(m.subs[2].type=="localname")
	 return m.subs[2].data, m.subs[1].data
      end -- is there a packagename in the identifier?
   end -- did we get an identifier?
end
	    
-- Lookup an identifier in the engine's environment, and get a human-readable definition of it
-- (reconstituted from its ast).  If identifier is null, return the entire environment.
local function get_environment(en, identifier)
   local env = en.env
   if identifier then
      local localname, prefix = parse_identifier(en, identifier)
      local val = lookup(en.env, localname, prefix)
--      if not environment.is(val) then
	 return val and properties(identifier, val)
--      else
--	 env = val
--      end
   end
   local flat_env = environment.flatten(env)
   -- Rewrite the flat_env table, replacing the pattern with a table of properties
   for id, pat in pairs(flat_env) do flat_env[id] = properties(id, pat); end
   return flat_env
end

local function clear_environment(en, identifier)
   if identifier then
      if lookup(en.env, identifier) then bind(en.env, identifier, nil); return true
      else return false; end
   else -- no identifier arg supplied, so wipe the entire env
      en.env = environment.new()
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
   if type(infilename)~="string" then e:error("bad input file name"); end
   if type(outfilename)~="string" then e:error("bad output file name"); end
   if type(errfilename)~="string" then e:error("bad error file name"); end   
   local infile, outfile, errfile, msg
   if #infilename==0 then infile = io.stdin;
   else infile, msg = io.open(infilename, "r"); if not infile then e:error(msg); end; end
   if #outfilename==0 then outfile = io.stdout
   else outfile, msg = io.open(outfilename, "w"); if not outfile then e:error(msg); end; end
   if #errfilename==0 then errfile = io.stderr;
   else errfile, msg = io.open(errfilename, "w"); if not errfile then e:error(msg); end; end
   return infile, outfile, errfile
end

local function engine_process_file(e, expression, trace_flag, infilename, outfilename, errfilename, wholefileflag)
   if type(trace_flag)~="boolean" then e:error("bad trace flag"); end
   --
   -- Set up pattern to match.  Always compile it first, even if we are going to call tracematch later.
   -- This is so that we report errors uniformly at this point in the process, instead of after
   -- opening the files.
   --
   local r, msgs
   if engine_module.rplx.is(expression) then
      r = expression
   else
      r, msgs = e:compile(expression)
      if not r then e:error(table.concat(msgs, '\n')); end
   end
   assert(engine_module.rplx.is(r))

   -- This set of simple optimizations almost doubles performance of the loop through the file
   -- (below) in typical cases, e.g. syslog pattern. 
   local encoder = e.encode_function		    -- optimization
   local built_in_encoder = type(encoder)=="number" and encoder
   if built_in_encoder then encoder = false; end
   local peg = r.pattern.peg			    -- optimization
   local matcher = function(input, start)
		      return rmatch(peg, input, start, built_in_encoder)
		   end                              -- FUTURE: inline this for performance

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
   if not ok then e:error(l); end
   local _, m, leftover, trace
   while l do
      if trace_flag then _, _, trace = e:trace(expression, l); end
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

function process_input_file.match(e, expression, infilename, outfilename, errfilename, wholefileflag)
   return engine_process_file(e, expression, false, infilename, outfilename, errfilename, wholefileflag)
end

function process_input_file.trace(e, expression, infilename, outfilename, errfilename, wholefileflag)
   return engine_process_file(e, expression, true, infilename, outfilename, errfilename, wholefileflag)
end

---------------------------------------------------------------------------------------------------

local function create_engine(name, compiler, searchpath)
   compiler = compiler or default_compiler
   searchpath = searchpath or default_searchpath
   if not compiler then error("no default compiler set"); end
   return engine.factory { name=function() return name; end,
			   compiler=compiler,
			   searchpath=searchpath,
			   env=environment.new(),
			   pkgtable=environment.make_module_table(),
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

		     encode_function=false,	      -- false or nil ==> use default encoder
		     output=get_set_encoder_function,

		     lookup=get_environment,
		     clear=clear_environment,

		     load=load,
		     loadfile=loadfile,
		     import=import,
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

local create_rplx = function(en, pattern)			    
		       return rplx.factory{ engine=en,
					    pattern=pattern,
					    match=function(...)
						     local ok, m, left, t0, t1 = en:match(...)
						     assert(ok, "precompiled pattern failed to compile?")
						     return m, left, t0, t1
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
