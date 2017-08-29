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
-- ROSIE_DEV will be true iff rosie is running in "development mode".  Certain errors that are
--            normally fatal will instead return control to the Lua interpreter (after being
--            signaled) when in development mode.  The value of ROSIE_DEV is set by the script
--            that launches the rosie CLI.
--
-- ROSIE_LIB is the variable that the rosie code uses to find the standard RPL library.  Its
--           value is ROSIE_HOME/rpl.  Currently, there is no way to change it externally.  If
--           needed, a ROSIE_LIB environment variable could be introduced in future.
--           
-- ROSIE_PATH is a list of directories that will be searched when looking for imported modules.
--           If this variable is not set in the environment or via the API/CLI, its value is the
--           single directory named by ROSIE_LIB.  This is currently the ONLY configuration
--           parameter that the user can control via the environment. 

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
   if ROSIE_DEV then error(msg, 3)
   else io.stderr:write(msg); os.exit(-3); end
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
-- When init is loaded from run-rosie, ROSIE_DEV will be a boolean (as set by cli.lua)
-- When init is loaded from rosie.lua, ROSIE_DEV will be unset.  In this case, it should be set to
-- true so that rosie errors do not invoke os.exit().
ROSIE_DEV = ROSIE_DEV or (ROSIE_DEV==nil)
ROSIE_VERBOSE = false
ROSIE_VERSION = read_version_or_die(ROSIE_HOME)
ROSIE_COMMAND = ""				    -- will be set by cli, if cli is invoked

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
   ROSIE_LIB = common.path(ROSIE_HOME, "rpl")
   ROSIE_PATH = ROSIE_LIB
   local ok, value = pcall(os.getenv, "ROSIE_PATH")
   if (not ok) then init_error('Internal error: call to os.getenv(ROSIE_PATH)" failed'); end
   if value then ROSIE_PATH = value; end
   assert(type(ROSIE_PATH)=="string")
end


local function load_all()
   cjson = import("cjson")
   lpeg = import("lpeg")
   readline = import("readline")

   -- These MUST have a partial order so that dependencies can be loaded first
   recordtype = import("recordtype")
   thread = import("thread")
   violation = import("violation")
   list = import("list")
   util = import("util")
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
   if ROSIE_DEV then
      print(name .. " created, accepting ".. tostring(engine.compiler.version))
   end
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
   local NEWCORE_ENGINE = engine.new("NEW RPL core engine", COREcompiler2, ROSIE_LIB)
   announce("NEWCORE_ENGINE", NEWCORE_ENGINE)
   return NEWCORE_ENGINE
end

function create_rpl_1_1_engine(e)
--   common.notes = true

   assert( (e:import("rosie/rpl_1_1", ".")) )
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

   local c2engine = engine.new("NEW RPL 1.1 engine (c2)", compiler2, ROSIE_LIB)

   -- Make the c2 compiler the default for new engines
   engine_module.set_default_compiler(compiler2)
   engine_module.set_default_searchpath(ROSIE_PATH)
   
   announce("c2 engine", c2engine)

   return c2engine

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

function populate_info()
   local rpl_version = engine_module.get_default_compiler().version
   ROSIE_INFO = {
      {name="ROSIE_VERSION", value=tostring(ROSIE_VERSION),             desc="version of rosie cli/api"},
      {name="ROSIE_HOME",    value=ROSIE_HOME,                          desc="location of the rosie installation directory"},
      {name="ROSIE_DEV",     value=tostring(ROSIE_DEV),                 desc="true if rosie was started in development mode"},
      {name="ROSIE_LIB",     value=tostring(ROSIE_LIB),                 desc="location of the standard rpl library"},
      {name="ROSIE_PATH",    value=tostring(ROSIE_PATH),                desc="directories to search for modules"},
      {name="RPL_VERSION",   value=tostring(rpl_version),               desc="version of rpl (language) accepted"},
      {name="HOSTNAME",      value=os.getenv("HOSTNAME") or "",         desc="host on which rosie is running"},
      {name="HOSTTYPE",      value=os.getenv("HOSTTYPE") or "",         desc="type of host on which rosie is running"},
      {name="OSTYPE",        value=os.getenv("OSTYPE") or "",           desc="type of OS on which rosie is running"},
      {name="CWD",           value=os.getenv("PWD") or "",              desc="current working directory"},
      {name="ROSIE_COMMAND", value=ROSIE_COMMAND or "",                 desc="invocation command, if rosie invoked through the CLI"}
   }
   for _,entry in ipairs(ROSIE_INFO) do ROSIE_INFO[entry.name] = entry.value; end
end

----------------------------------------------------------------------------------------
-- Output encoding functions
----------------------------------------------------------------------------------------

-- Map encoder names to the internal value needed to use them

function create_encoder_table()
   return {
      line = 2,
      json = 1,
      byte = 0,
      color = function(m) return color.match(m, color.colormap); end,

      nocolor = function(m) return color.match(m, {}); end,
      text = function(m) return m.data end,	    -- only the matching text
      subs = function(m)			    -- each submatch on its own line
		return table.concat(list.map(function(sub) return sub.data end,
					     m.subs),
				    "\n")
	     end,
      none = false,
      [false] = false,
   }
end

----------------------------------------------------------------------------------------
-- Provide an API for setting/checking modes
----------------------------------------------------------------------------------------

-- local mode_table = {}
-- function setmode(name, optional_value)
--    mode_table[name] = (optional_value==nil and false) or optional_value or true
-- end
-- function mode(name)
--    return mode_table[name]
-- end

----------------------------------------------------------------------------------------
-- Build the rosie module as seen by the Lua client
----------------------------------------------------------------------------------------

local rosie_package = {}

rosie_package.env = _ENV
load_all()
setup_paths()
CORE_ENGINE = create_core_engine()

ROSIE_ENGINE = create_rpl_1_1_engine(CORE_ENGINE)
assert(ROSIE_ENGINE)
populate_info()

rosie_package.engine = engine
rosie_package.encoders = create_encoder_table()
rosie_package.info = function(...) return ROSIE_INFO; end
rosie_package.import = import

-- rosie_package.setmode = setmode
-- rosie_package.mode = mode

collectgarbage("setpause", 194)

return rosie_package


