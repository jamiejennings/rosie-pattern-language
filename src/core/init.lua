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
   if ROSIE_DEV then
      error(msg)
   else
      io.stderr:write(msg); os.exit(-3)
   end
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
   list = import("list")
   util = import("util")
   common = import("common")
   environment = import("environment")
   writer = import("writer")
   syntax = import("syntax")
   parse = import("parse")
   rpl_parser = import("rpl-parser")
   ast = import("ast")
   c0 = import("c0")
   c1 = import("c1")
   compile = import("compile")
   color_output = import("color-output")
   eval = import("eval")
   engine_module = import("engine_module")
   ui = import("ui")

   engine = engine_module.engine

   process_rpl_file = import("process_rpl_file")

end

---------------------------------------------------------------------------------------------------
-- Bootstrap the rpl parser, which is defined using "rpl 1.0" (defined in parse.lua)
---------------------------------------------------------------------------------------------------
-- 
-- The engines we create now will use parse.core_parse, which defines "rpl 0.0", i.e. the core
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

local unsupported = function() init_error("operation not supported in this parser"); end

local function create_core_engine()
   assert(parse.core_parse, "error while initializing: parse module not loaded?")
   assert(syntax.transform0, "error while initializing: syntax module not loaded?")

   local function make_parser_expander(parser)
      return function(source)
		local ast, msgs, leftover = parser(source)
		if not ast then
		   return nil, nil, msgs, leftover
		else
		   return syntax.transform0(ast), ast, msgs, leftover
		end
	     end
   end

   core_parser =
      common.parser.new{ version = common.rpl_version.new(0, 0);
			 preparse = unsupported;
			 parse_statements = make_parser_expander(parse.core_parse);
			 parse_expression = make_parser_expander(parse.core_parse_expression);
			 parse_deps = function() return {} end;
			 prefixes = unsupported;
		      }
   corecompiler =
      common.compiler.new{ version = common.rpl_version.new(0, 0);
			   load = compile.compile0.compile;
			   import = unsupported;
			   compile_expression = compile.compile0.compile_expression;
			   parser = core_parser;
			}

   -- Create a core engine that accepts rpl 0.0
   CORE_ENGINE = engine.new("RPL core engine", corecompiler)
   CORE_ENGINE.searchpath = ROSIE_LIB
   announce("CORE_ENGINE", CORE_ENGINE)

   -- Into the core engine, load the rpl 1.0 definition, which is written in rpl 0.0
   local rpl_1_0_filename = common.path(ROSIE_LIB, "rosie", "rpl_1_0.rpl")
   local rpl_1_0, msg = util.readfile(rpl_1_0_filename)

   if not rpl_1_0 then error("Error while reading " .. rpl_1_0_filename .. ": " .. msg); end
   local success, pkg, messages = CORE_ENGINE:load(rpl_1_0, "rosie/rpl_1_0.rpl")

   local success, result, messages = pcall(CORE_ENGINE.compile, CORE_ENGINE, 'rpl_statements', 'match')
   if not success then error("Error while initializing: could not compile 'rpl_statements' in "
			     .. rpl_1_0_filename .. ":\n" .. tostring(result)); end
   ROSIE_RPLX = result

   local success, result, messages = pcall(CORE_ENGINE.compile, CORE_ENGINE, 'rpl_expression', 'match')
   if not success then error("Error while initializing: could not compile 'rpl_expression' in "
			     .. rpl_1_0_filename .. ":\n" .. tostring(result)); end
   ROSIE_EXP_RPLX = result

   local success, result, messages = pcall(CORE_ENGINE.compile, CORE_ENGINE, 'preparse', 'match')
   if not success then error("Error while initializing: could not compile 'preparse' in "
			     .. rpl_1_0_filename .. ":\n" .. tostring(result)); end
   ROSIE_PREPARSE = result
end


function create_rpl1_0_engine()
   -- Install the fancier parser, parse_and_explain, which uses ROSIE_RPLX and ROSIE_PREPARSE
   local supported_version = common.rpl_version.new(1, 0)
   local preparser =
      rpl_parser.make_preparser(ROSIE_PREPARSE, supported_version);
   local parse_and_explain =
      rpl_parser.make_parse_and_explain(preparser, supported_version, ROSIE_RPLX, syntax.transform0)
   local parse_and_explain_exp =
      rpl_parser.make_parse_and_explain(nil, nil, ROSIE_EXP_RPLX, syntax.transform0)

   parser1_0 =
      common.parser.new{ version = supported_version;
			 preparse = preparser;
			 parse_statements = parse_and_explain;
			 parse_expression = parse_and_explain_exp;
			 parse_deps = function() return {} end;
			 prefixes = unsupported;
		      }
   compiler1_0 =
      common.compiler.new{ version = common.rpl_version.new(1, 0);
			   load = compile.compile0.compile;
			   import = unsupported;
			   compile_expression = compile.compile0.compile_expression;
			   parser = parser1_0;
			}
   RPL1_0_ENGINE = engine.new("RPL 1.0 engine", compiler1_0)
   RPL1_0_ENGINE.searchpath = ROSIE_LIB
   announce("RPL1_0_ENGINE", RPL1_0_ENGINE)
end

function create_rpl1_1_engine()
   -- Create an engine, and load the rpl 1.1 definition, which is written in rpl 1.0
   local rpl_1_1_filename = ROSIE_HOME.."/rpl/rosie/rpl_1_1.rpl"
   local rpl_1_1, msg = util.readfile(rpl_1_1_filename)
   if not rpl_1_1 then error("Error while reading " .. rpl_1_1_filename .. ": " .. msg); end
   local e = engine.new("RPL 1.1 engine", compiler1_0)
   e.searchpath = ROSIE_LIB
   e:load(rpl_1_1, "rosie/rpl_1_1.rpl")
   local messages
   RPL1_1_RPLX, messages = e:compile('rpl_statements')
   RPL1_1_EXP_RPLX, messages = e:compile('rpl_expression')
   rpl_parser = import("rpl-parser")		    -- idempotent
   local supported_version = common.rpl_version.new(1, 1)
   local preparser =
      rpl_parser.make_preparser(ROSIE_PREPARSE, supported_version);
   local parse_and_explain =
      rpl_parser.make_parse_and_explain(preparser, supported_version, RPL1_1_RPLX, syntax.transform1)
   local parse_and_explain_exp =
      rpl_parser.make_parse_and_explain(nil, nil, RPL1_1_EXP_RPLX, syntax.transform1)

   parser1_1 =
      common.parser.new{ version = supported_version;
			 preparse = preparser;
			 parse_statements = parse_and_explain;
			 parse_expression = parse_and_explain_exp;
			 parse_deps = rpl_parser.parse_deps;
			 prefixes = unsupported;	       -- FIXME
		      }
   compiler1_1 =
      common.compiler.new{ version = supported_version;
			   load = compile.compile1.compile;
			   import = unsupported;               -- FIXME
			   compile_expression = compile.compile1.compile_expression;
			   parser = parser1_1;
			}

   -- Make RPL 1.1 the default for new engines
   engine_module._set_default_compiler(compiler1_1)
   engine_module._set_default_searchpath(ROSIE_PATH)

   RPL1_1_ENGINE = e
   announce("RPL1_1_ENGINE", RPL1_1_ENGINE)

   ROSIE_ENGINE = RPL1_1_ENGINE
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
   local rpl_version = engine_module._get_default_compiler().version
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
      color = color_output.color_string_from_leaf_nodes,
      nocolor = color_output.string_from_leaf_nodes,
      fulltext = function(m) return m.text end,
      none = false;
      [false] = false;
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

rosie_package._env = _ENV
load_all()
setup_paths()
create_core_engine()
create_rpl1_0_engine()
create_rpl1_1_engine()
assert(ROSIE_ENGINE)
populate_info()

rosie_package.engine = engine
rosie_package.encoders = create_encoder_table()
rosie_package.info = function(...) return ROSIE_INFO; end
rosie_package.import = import

rosie_package.setmode = setmode
rosie_package.mode = mode

collectgarbage("setpause", 194)

return rosie_package


