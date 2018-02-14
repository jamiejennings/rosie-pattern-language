---- -*- Mode: Lua; -*-                                                                           
----
---- init.lua    Load the Rosie system, given the location of the installation directory
----
---- © Copyright IBM Corporation 2016, 2017.
---- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
---- AUTHOR: Jamie A. Jennings

----------------------------------------------------------------------------------------
-- Explanation of key globals
----------------------------------------------------------------------------------------
-- 
-- ROSIE_HOME indicates from where this executing instance of rosie is running.  It will
--            typically be a system location like /usr/local/lib/rosie, but could also
--            be any local rosie install directory, like ~/rosie.  In the filesystem at
--            ROSIE_HOME are: 
--              ROSIE_HOME/rpl the rosie standard library
--              ROSIE_HOME/bin executables
--              ROSIE_HOME/lib files needed by executables
--              ROSIE_HOME/doc documentation
--              ROSIE_HOME/man man pages (documentation in the unix style)
--            The value of ROSIE_HOME is set in the script that launches the rosie CLI.
--
-- ROSIE_LIBDIR is the variable that the rosie code uses to find the standard RPL library.  Its
--           value is ROSIE_HOME/rpl.  Currently, there is no way to change it externally.  If
--           needed, a ROSIE_LIBDIR environment variable could be introduced in future.
--           
-- ROSIE_LIBPATH is a list of directories that will be searched when looking for imported
--           modules. If this variable is not set in the environment or via the API/CLI, its value
--           is the single directory named by ROSIE_LIBDIR.  This is currently the ONLY
--           configuration parameter that the user can control via the environment.

----------------------------------------------------------------------------------------
-- Define key globals
----------------------------------------------------------------------------------------
-- The value of ROSIE_HOME on entry to this file is set by either:
--    (1) The shell script bin/rosie, which was
--         - created by the Rosie installation process (Makefile), to include the value
--           of ROSIE_HOME. 
--         - When that script is invoked by the user in order to run Rosie,
--           the script passes ROSIE_HOME to cli.lua, which has called this file (init).
-- Or (2) The code in rosie.lua, which was also created by the Rosie installation.

local io = require "io"
local os = require "os"

local function init_error(msg)
   error(msg, 3)
end
   
local function read_version_or_die(home)
   assert(type(home)=="string")
   local vfile = io.open(home.."/VERSION")
   if vfile then
      local v = vfile:read("l"); vfile:close();
      if v then return v; end			    -- success
   end
   -- otherwise either vfile is nil or v is nil
   init_error("Error while initializing: "..tostring(home)
	   .."/VERSION does not exist or is not readable\n")
end

if not ROSIE_HOME then error("Error while initializing: internal variable ROSIE_HOME not set"); end
ROSIE_VERBOSE = false
ROSIE_VERSION = read_version_or_die(ROSIE_HOME)

import('strict')(_G)				    -- do this AFTER checking the ROSIE_* globals

---------------------------------------------------------------------------------------------------
-- Make some standard libraries available, and do some essential checks to make sure we can run
---------------------------------------------------------------------------------------------------
table = require "table"
os = require "os"
math = require "math"

-- Ensure we can fit any current (up to 0x10FFFF) and future (up to 0xFFFFFFFF) Unicode code
-- points in a single Lua integer.
if (not math) then
   error("Internal error: math functions unavailable")
elseif (0xFFFFFFFF > math.maxinteger) then
   error("Internal error: max integer on this platform is too small")
end

---------------------------------------------------------------------------------------------------
-- Load the entire rosie world... (which includes the "core" parser for "rpl 1.0")
---------------------------------------------------------------------------------------------------

local function setup_paths()
   ROSIE_LIBDIR = common.path(ROSIE_HOME, "rpl")
   ROSIE_LIBPATH = ROSIE_LIBDIR
   ROSIE_LIBPATH_SOURCE = "lib"
   local ok, value = pcall(os.getenv, "ROSIE_LIBPATH")
   if (not ok) then init_error('Internal error: call to os.getenv(ROSIE_LIBPATH)" failed'); end
   if value then
      ROSIE_LIBPATH = value;
      ROSIE_LIBPATH_SOURCE = "env";
   end
   assert(type(ROSIE_LIBPATH)=="string")
end


local function load_all()
   lpeg = import("lpeg")

   -- Each Lua state gets its own cjson instance
   cjson_lib = import("cjson.safe")
   cjson = cjson_lib.new()
   package.loaded.cjson = cjson

   -- These MUST have a partial order so that dependencies can be loaded first
   recordtype = import("recordtype")
   thread = import("thread")
   violation = import("violation")
   list = import("list")
   util = import("util")
   ustring = import("ustring")
   common = import("common")
   color = import("color")
   writer = import("writer")
   parse_core = import("parse_core")
   parse = import("parse")
   ast = import("ast")
   builtins = import("builtins")
   environment = import("environment")
   expand = import("expand")
   compile = import("compile")
   loadpkg = import("loadpkg")
   trace = import("trace")
   rcfile = import("rcfile")
   engine_module = import("engine_module")
   engine = engine_module.engine
   ui = import("ui")

end

---------------------------------------------------------------------------------------------------
-- Bootstrap the rpl parser, which is defined using "rpl 1.0" (defined in parse_core.lua)
---------------------------------------------------------------------------------------------------
-- 
-- The engines we create now will use parse_core.parse, which defines "rpl 0.0", i.e. the core
-- language (which has many limitations).
-- 
-- An engine that accepts "rpl 0.0" is needed to parse $ROSIE_HOME/rpl/rosie/rpl_1_0.rpl, which defines
-- "rpl 1.0".  This is the version of rpl used for the Rosie v0.99x releases.
--

local function announce(name, engine)
-- FUTURE: Create a way to check if logging is enabled, and announce engine creation only then.
end

function create_core_engine()
   assert(parse_core.rpl, "error while initializing: parse module not loaded?")

   local core_parser = function(source_record, messages)
			  local pt = parse_core.rpl(source_record, messages)
			  return ast.from_core_parse_tree(pt, source_record)
		       end

   local core_expression_parser = function(source_record, messages)
				     local pt = parse_core.expression(source_record, messages)
				     return ast.from_core_parse_tree(pt, source_record)
				  end

   local COREcompiler2 = { version = common.rpl_version.new(0, 0),
			   parse_block = core_parser,
			   expand_block = compile.expand_block,
			   compile_block = compile.compile_block,
			   dependencies_of = compile.dependencies_of,
			   parse_expression = core_expression_parser,
			   expand_expression = compile.expand_expression,
			   compile_expression = compile.compile_expression,
		        }
   -- Create a core engine that loads/compiles rpl 0.0
   local NEWCORE_ENGINE = engine.new("NEW RPL core engine", COREcompiler2, ROSIE_LIBDIR)
   announce("NEWCORE_ENGINE", NEWCORE_ENGINE)
   return NEWCORE_ENGINE
end

function create_rpl_1_1_engine(e)
--   common.notes = true

   local ok, pkg, messages = e:import("rosie/rpl_1_1", ".")
   assert(ok, util.table_to_pretty_string(messages, false))

   local version = common.rpl_version.new(1, 1)
   local rplx_preparse, errs = e:compile("preparse")
   assert(rplx_preparse, errs and util.table_to_pretty_string(errs) or "no err info")
   local rplx_statements = e:compile("rpl_statements")
   assert(rplx_statements)
   local rplx_expression = e:compile("rpl_expression")
   assert(rplx_expression)

   compiler2 = { version = version,
		 parse_block = compile.make_parse_block(rplx_preparse, rplx_statements, version),
	         expand_block = compile.expand_block,
	         compile_block = compile.compile_block,
	         dependencies_of = compile.dependencies_of,
	         parse_expression = compile.make_parse_expression(rplx_expression),
	         expand_expression = compile.expand_expression,
	         compile_expression = compile.compile_expression,
	   }

   local c2engine = engine.new("NEW RPL 1.1 engine (c2)", compiler2, ROSIE_LIBDIR)

   -- Make the c2 compiler the default for new engines
   engine_module.set_default_compiler(compiler2)
   engine_module.set_default_searchpath(ROSIE_LIBPATH)
   
   announce("c2 engine", c2engine)

   return c2engine

end

function create_rpl_1_2_engine(e)
--   common.notes = true

   local ok, pkg, messages = e:import("rosie/rpl_1_2", ".")
   assert(ok, util.table_to_pretty_string(messages, false))

   local version = common.rpl_version.new(1, 2)
   local rplx_preparse, errs = e:compile("preparse")
   assert(rplx_preparse, errs and util.table_to_pretty_string(errs) or "no err info")
   local rplx_statements = e:compile("rpl_statements")
   assert(rplx_statements)
   local rplx_expression = e:compile("rpl_expression")
   assert(rplx_expression)

   compiler3 = { version = version,
		 parse_block = compile.make_parse_block(rplx_preparse, rplx_statements, version),
	         expand_block = compile.expand_block,
	         compile_block = compile.compile_block,
	         dependencies_of = compile.dependencies_of,
	         parse_expression = compile.make_parse_expression(rplx_expression),
	         expand_expression = compile.expand_expression,
	         compile_expression = compile.compile_expression,
	   }

   local c3engine = engine.new("NEW RPL 1.2 engine (c3)", compiler3, ROSIE_LIBDIR)

   -- Make the c3 compiler the default for new engines
    engine_module.set_default_compiler(compiler3)
    engine_module.set_default_searchpath(ROSIE_LIBPATH)
   
   announce("c3 engine", c3engine)

   return c3engine

end

----------------------------------------------------------------------------------------
-- INFO for debugging
----------------------------------------------------------------------------------------

-- N.B. All values in table must be strings, even if original value was nil or another type.
-- Two ways to use this table:
-- (1) Iterate over the numeric entries with ipairs to access an organized (well, ordered) list of
--     important parameters, with their values and descriptions.
-- (2) Index the table by a parameter key to obtain its value.

ROSIE_INFO = {}

-- FUTURE: Re-do this data structure?

-- ROSIE_INFO is a list ordered for presentation clarity.  Access to a value using its name is a
-- linear time operation, although the table size is small.

local function populate_info()
   local rpl_version = engine_module.get_default_compiler().version
   ROSIE_INFO = {
      {name="ROSIE_VERSION", value=tostring(ROSIE_VERSION),             desc="version of rosie cli/api"},
      {name="ROSIE_HOME",    value=ROSIE_HOME,                          desc="location of the rosie installation directory"},
      {name="ROSIE_LIBDIR",  value=tostring(ROSIE_LIBDIR),              desc="location of the standard rpl library"},
      {name="ROSIE_LIBPATH", value=tostring(ROSIE_LIBPATH),             desc="directories to search for modules"},
      {name="ROSIE_LIBPATH_SOURCE", value=tostring(ROSIE_LIBPATH_SOURCE), desc="how ROSIE_LIBPATH was set: lib/env/cli/api"},
      {name="RPL_VERSION",   value=tostring(rpl_version),               desc="version of rpl (language) accepted"},
      {name="HOSTTYPE",      value=os.getenv("HOSTTYPE") or "",         desc="type of host on which rosie is running"},
      {name="OSTYPE",        value=os.getenv("OSTYPE") or "",           desc="type of OS on which rosie is running"},
      {name="ROSIE_COMMAND", value=ROSIE_COMMAND or "",                 desc="invocation command, if rosie invoked through the CLI"}
   }
   local function search_by_name(self, name)
      if type(name) ~= "string" then return nil; end
      for _, entry in ipairs(self) do
	 if rawget(entry, "name") == name then return rawget(entry, "value"); end
      end
      error("Internal error: configuration key not found: " .. tostring(name))
   end
   setmetatable(ROSIE_INFO, {__index = search_by_name})
end

local function set_configuration(key, value)
   for _,entry in ipairs(ROSIE_INFO) do
      if entry.name == key then
	 entry.value = value
	 return 
      end
   end -- for
   error("Internal error: configuration key not found: " .. tostring(key))
end

----------------------------------------------------------------------------------------
-- Build the rosie module as seen by the Lua client
----------------------------------------------------------------------------------------

local rosie_package = {}

rosie_package.env = _ENV
load_all()
setup_paths()

common.add_encoder("color", common.BYTE_ENCODER,
		   function(m, input, start, parms)
		      return color.match(common.byte_to_lua(m, input), input, parms.colors)
		   end)
common.add_encoder("matches", common.BYTE_ENCODER,
		   function(m, input, start)
		      m = common.byte_to_lua(m, input)
		      return m.data
		   end)
common.add_encoder("subs", common.BYTE_ENCODER,
		   function(m, input, start)
		      m = common.byte_to_lua(m, input)
		      if m.subs then
			 return table.concat(list.map(function(sub)
							 return sub.data
						      end,
						      m.subs),
					     "\n")
		      else
			 return nil
		      end
		   end)
common.add_encoder("jsonpp", common.BYTE_ENCODER,
		   function(m, input, start)
		      local max_length = false
		      local json_style = true
		      m = common.byte_to_lua(m, input)
		      return util.table_to_pretty_string(m, max_length, json_style)
		   end)

rosie_package.set_configuration = set_configuration
rosie_package.config = function(...) return ROSIE_INFO; end

-- Set the default libpath for any engines created later
rosie_package.set_libpath =
   function(newlibpath, bywhom)
      set_configuration("ROSIE_LIBPATH", tostring(newlibpath))
      set_configuration("ROSIE_LIBPATH_SOURCE", tostring(bywhom or "unknown"))
      engine_module.set_default_searchpath(newlibpath)
   end

rosie_package.encoders = common.encoder_table
rosie_package.engine = engine
rosie_package.import = import

-- rosie_package.setmode = setmode
-- rosie_package.mode = mode

-- The magic number for setpause was determined experimentally.  The key property is that it is
-- just less than 200, which is the default value, making the collector more aggressive.
collectgarbage("setpause", 194)

CORE_ENGINE = create_core_engine()

ROSIE_ENGINE = create_rpl_1_2_engine(CORE_ENGINE)
assert(ROSIE_ENGINE)

--NEW_ENGINE = create_rpl_1_2_engine(create_core_engine())
--assert(NEW_ENGINE)

-- Call populate_info() after building up a default compiler and setting that
-- default in the engine module.
populate_info()

--common.notes = true

return rosie_package


