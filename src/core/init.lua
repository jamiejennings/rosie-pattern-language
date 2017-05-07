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
--
-- ROSIE_LIB is the variable that the rosie code uses to find the standard RPL library.
--           Unless the user supplies a different value (by setting the environment
--           variable ROSIE_LIB), the value is the set to ROSIE_HOME/rpl.  This is currently
--           the ONLY configuration parameter that the user can control via the environment.
--
-- ROSIE_DEV  will be true iff rosie is running in "development mode".  Certain errors
--            that are normally fatal will instead return control to the Lua interpreter
--            (after being signaled) when in development mode.

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

local function read_version_or_die(home)
   assert(type(home)=="string")
   local vfile = io.open(home.."/VERSION")
   if vfile then
      local v = vfile:read("l"); vfile:close();
      if v then return v; end			    -- success
   end
   -- otherwise either vfile is nil or v is nil
   local msg = "Error while initializing: "..tostring(home).."/VERSION does not exist or is not readable\n"
   if not ROSIE_DEV then io.stderr:write(msg); os.exit(-3); end
   error(msg)					    -- should do throw(msg) to end of init?
end

function setup_globals()
   if not ROSIE_HOME then error("Error while initializing: variable ROSIE_HOME not set"); end
   -- When init is loaded from run-rosie, ROSIE_DEV will be a boolean (as set by cli.lua)
   -- When init is loaded from rosie.lua, ROSIE_DEV will be unset.  In this case, it should be set to
   -- true so that rosie errors do not invoke os.exit().
   ROSIE_DEV = ROSIE_DEV or (ROSIE_DEV==nil)
   ROSIE_VERSION = read_version_or_die(ROSIE_HOME)
   -- The location of the Rosie standard library (of patterns) is ROSIE_LIB/rpl.
   -- And compiled Rosie packages are stored in ROSIE_LIB/pkg.
   --
   -- ROSIE_LIB = ROSIE_HOME by default.  The user can override the default by setting the
   -- environment variable $ROSIE_LIB to point somewhere else.
   ROSIE_LIB = ROSIE_HOME
   local ok, value = pcall(os.getenv, "ROSIE_LIB")
   if (not ok) then error('Internal error: call to os.getenv(ROSIE_LIB)" failed'); end
   if value then ROSIE_LIB = value; end
end

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

function load_all()
   cjson = import("cjson")
   lpeg = import("lpeg")
   readline = import("readline")

   -- These MUST have a partial order so that dependencies can be loaded first
   recordtype = import("recordtype")
   util = import("util")
   common = import("common")
   environment = import("environment")
   list = import("list")
   writer = import("writer")
   syntax = import("syntax")
   parse = import("parse")
   c0 = import("c0")
   c1 = import("c1")
   compile = import("compile")
   eval = import("eval")
   color_output = import("color-output")
   engine_module = import("engine_module")
   ui = import("ui")

   engine = engine_module.engine

   -- manifest code requires a working engine, so we initialize the engine package here
   assert(parse.core_parse, "error while initializing: parse module not loaded?")
   assert(syntax.transform0, "error while initializing: syntax module not loaded?")
   local function rpl_parser(source)
      local astlist, msgs, leftover = parse.core_parse(source)
      if not astlist then
	 return nil, nil, msgs, leftover
      else
	 return syntax.transform0(astlist), astlist, msgs, leftover
      end
   end

   engine_module._set_defaults(rpl_parser, compile.compile0, 0, 0);
--   manifest = import("manifest")

   process_input_file = import("process_input_file")
   process_rpl_file = import("process_rpl_file")

   assert(_G)
   argparse = import("argparse")

end

---------------------------------------------------------------------------------------------------
-- Bootstrap the rpl parser, which is defined using "rpl 1.0" (defined in parse.lua)
---------------------------------------------------------------------------------------------------
-- 
-- The engines we create now will use parse.core_parse, which defines "rpl 0.0", i.e. the core
-- language (which has many limitations).
-- 
-- An engine that accepts "rpl 0.0" is needed to parse $ROSIE_HOME/rpl/rpl-1.0.rpl, which defines
-- "rpl 1.0".  This is the version of rpl used for the Rosie v0.99x releases.
--

local function announce(name, engine)
   if ROSIE_DEV then
      print(name .. " created: _rpl_version = ".. tostring(engine._rpl_version) ..
	                    "; _rpl_parser = " .. tostring(engine._rpl_parser))
   end
end

function create_core_engine()
   -- Create a core engine that accepts rpl 0.0
   -- N.B. default rpl parser has been set in load-modules because manifest package needs it
   CORE_ENGINE = engine.new("RPL core engine")
   announce("CORE_ENGINE", CORE_ENGINE)
   -- Into the core engine, load the rpl 1.0 definition, which is written in rpl 0.0
   local rpl_1_0_filename = ROSIE_HOME.."/rpl/rpl-1.0.rpl"
   local rpl_1_0, msg = util.readfile(rpl_1_0_filename)
   if not rpl_1_0 then error("Error while reading " .. rpl_1_0_filename .. ": " .. msg); end
   CORE_ENGINE:load(rpl_1_0)
   CORE_ENGINE:compile('rpl', 'match')

   
   local success, result, messages = pcall(CORE_ENGINE.compile, CORE_ENGINE, 'rpl', 'match')
   if not success then error("Error while initializing: could not compile 'rpl' in "
			     .. rpl_1_0_filename .. ":\n" .. tostring(result)); end
   ROSIE_RPLX = result
   local success, result, messages = pcall(CORE_ENGINE.compile, CORE_ENGINE, 'preparse', 'match')
   if not success then error("Error while initializing: could not compile 'preparse' in "
			     .. rpl_1_0_filename .. ":\n" .. tostring(result)); end
   ROSIE_PREPARSE = result
end

-- function make_compile0(en)
--    return {compile = function(astlist, original_astlist, source, env)
-- 			return compile.compile1.compile(en._rpl_parser, source, env, en._modtable, "")
-- 		     end,
-- 	   compile_expression = compile.compile0.compile_expression}
-- end

function create_rosie_engine()
   -- Install the fancier parser, parse_and_explain, which uses ROSIE_RPLX and ROSIE_PREPARSE
   rpl_parser = import("rpl-parser")
   local parse_and_explain = make_parse_and_explain(ROSIE_PREPARSE, ROSIE_RPLX, 1, 0, syntax.transform0)
   -- And make these the defaults for all new engines:
   ROSIE_ENGINE = engine.new("RPL 1.0 engine")
   engine_module._set_defaults(parse_and_explain, compile.compile0, 1, 0);
   announce("ROSIE_ENGINE", ROSIE_ENGINE)
end

function create_rpl1_1_engine()
   -- Create an engine, and load the rpl 1.1 definition, which is written in rpl 1.0
   local rpl_1_1_filename = ROSIE_HOME.."/rpl/rpl-1.1.rpl"
   local rpl_1_1, msg = util.readfile(rpl_1_1_filename)
   if not rpl_1_1 then error("Error while reading " .. rpl_1_1_filename .. ": " .. msg); end
   local e = engine.new("RPL 1.1 engine")
   e:load(rpl_1_1)
   local messages
   RPL1_1_RPLX, messages = e:compile('rpl_any')

   -- Install the fancier parser, parse_and_explain
   rpl_parser = import("rpl-parser")		    -- idempotent
   local parse_and_explain = make_parse_and_explain(ROSIE_PREPARSE, RPL1_1_RPLX, 1, 1, syntax.transform1)

   -- RPL 1.1 is now the default for new engines
   engine_module._set_defaults(parse_and_explain, compile.compile1, 1, 1);

   RPL1_1_ENGINE = e
   announce("RPL1_1_ENGINE", RPL1_1_ENGINE)
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
   ROSIE_INFO = {
      {name="ROSIE_HOME",    value=ROSIE_HOME,                          desc="location of the rosie installation directory"},
      {name="ROSIE_VERSION", value=ROSIE_VERSION,                       desc="version of rosie installed"},
      {name="RPL_VERSION",   value=tostring(ROSIE_ENGINE._rpl_version), desc="version of rpl (language) accepted"},
      {name="ROSIE_LIB",     value=tostring(ROSIE_LIB),                 desc="location of the standard rpl library"},
      {name="ROSIE_DEV",     value=tostring(ROSIE_DEV),                 desc="true if rosie was started in development mode"},
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
-- Lua applications (including the Rosie CLI & REPL) can use this table to install known
-- output encoders by name.

function create_encoder_table()
   return {
      line = 2,
      json = 1,
      byte = 0,
      color = color_output.color_string_from_leaf_nodes,
      nocolor = color_output.string_from_leaf_nodes,
      fulltext = common.match_to_text,
      none = false;
      [false] = false;
   }
end

----------------------------------------------------------------------------------------
-- Build the rosie module as seen by the Lua client
----------------------------------------------------------------------------------------
function create_file_functions()
   return {
      match = process_input_file.match,
      tracematch = process_input_file.tracematch,
      grep = process_input_file.grep,
      load = process_rpl_file.load_file	    -- TEMP until module system
   }
end

local rosie_package = {}

rosie_package._env = _ENV
setup_globals()
load_all()
create_core_engine()
create_rosie_engine()
create_rpl1_1_engine()
populate_info()
rosie_package.engine = engine
rosie_package.file = create_file_functions()
rosie_package.encoders = create_encoder_table()
rosie_package.info = function(...) return ROSIE_INFO; end

collectgarbage("setpause", 194)

return rosie_package


