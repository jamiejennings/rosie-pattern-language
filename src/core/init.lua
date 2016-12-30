---- -*- Mode: Lua; -*-                                                                           
----
---- init.lua    Load the Rosie system, given the location of the installation directory
----
---- © Copyright IBM Corporation 2016.
---- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
---- AUTHOR: Jamie A. Jennings

-- rosie.lua:
--   Usage: rosie = require "rosie"
--   The Rosie installation (Makefile) will create rosie.lua from src/rosie-package-template.lua


-- Current lapi functions, sorted by where they will end up:
--
-- + rosie.info()
--   home: "/Users/jjennings/Work/Dev/public/rosie-p...", 
--
-- + rosie.engine.new(optional_name)
--   new_engine: function: 0x7fc58cd196a0, 
--
-- rosie.file.match(engine, expression, infile, outfile, errfile)
-- rosie.file.eval(engine, expression, infile, outfile, errfile)
-- rosie.file.grep(engine, expression, infile, outfile, errfile)
--   eval_file: function: 0x7fc58cd1c8d0, 
--   match_file: function: 0x7fc58cd1c890}
--
-- engine:load(string, type)
--   load_manifest: function: 0x7fc58cd1c970, 
--   load_string: function: 0x7fc58cd1ca60, 
--   load_file: function: 0x7fc58cd1c9c0, 
--
-- + engine:lookup(optional_identifier)
--   get_environment: function: 0x7fc58cd1a640, 
--
-- + engine:clear(optional_identifier)
--   clear_environment: function: 0x7fc58cd19660, 
--
-- + engine:id()
-- + engine:name()
--   inspect_engine: function: 0x7fc58cd194d0, 
--
-- engine:match(expression, input)
--   match: function: 0x7fc58cd1c870, 
--
-- engine:eval(expression, input)
--   eval: function: 0x7fc58cd1c8b0, 
--
-- engine:grep(expression, input)
--   set_match_exp_grep_TEMPORARY: function: 0x7fc58cd1c8f0, 
--
-- engine:output(formatter)
--   configure_engine: function: 0x7fc58cd1cab0, 

----------------------------------------------------------------------------------------
-- First, set up some key globals
----------------------------------------------------------------------------------------
-- The value of ROSIE_HOME on entry to this file is set by either:
-- (1) The shell script bin/rosie, which was
--      - created by the Rosie installation process (Makefile), to include the value
--        of ROSIE_HOME. 
--      - When that script is invoked by the user in order to run Rosie,
--        the script passes ROSIE_HOME to run.lua (the CLI), which has called this file (init).
-- Or (2) The code in rosie.lua, which was also created by the Rosie installation.
if not ROSIE_HOME then error("Error while initializing: variable ROSIE_HOME not set"); end

-- When init is loaded from run-rosie, ROSIE_DEV will always be true or false 
-- When init is loaded from rosie.lua, ROSIE_DEV will be unset.  In this case, it should be set to
-- true so that rosie errors do not invoke os.exit().
if ROSIE_DEV==nil then ROSIE_DEV=true; end

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
   error(msg)					    -- should do throw(msg) to end of init
end

ROSIE_VERSION = read_version_or_die(ROSIE_HOME)

----------------------------------------------------------------------------------------
-- Load the entire rosie world...
----------------------------------------------------------------------------------------

local loader, msg = loadfile(ROSIE_HOME .. "/src/load-modules.lua", "t", _ENV)
if not loader then error("Error while initializing: " .. msg); end
loader()

----------------------------------------------------------------------------------------
-- Bootstrap the rpl parser, which is defined in a subset of rpl that is parsed by a
-- "native" (Lua lpeg) parser.
----------------------------------------------------------------------------------------

-- During bootstrapping, we have to compile the rpl using the "core" compiler, and
-- manually configure ROSIE_ENGINE without calling engine_configure.
-- To bootstrap, we have to compile the Rosie rpl using the core parser/compiler
-- Create a matching engine for processing Rosie Pattern Language files

load_module("rpl-parser")

ROSIE_ENGINE = engine.new("RPL engine")
compile.compile_core(ROSIE_HOME.."/src/rpl-core.rpl", ROSIE_ENGINE.env)
local success, result = compile.compile_match_expression('rpl', ROSIE_ENGINE.env)
if not success then error("Error while initializing: could not compile rosie core rpl: " .. tostring(result)); end

ROSIE_ENGINE.expression = 'rpl';
ROSIE_ENGINE.pattern = success;
ROSIE_ENGINE.encode = "null/bootstrap";
ROSIE_ENGINE.encode_function = function(m) return m; end;

-- Install the new parser.
compile.set_parser(parse_and_explain);

-- The location of the Rosie standard library (of patterns) is ROSIE_ROOT/rpl.
-- And compiled Rosie packages are stored in ROSIE_ROOT/pkg.
--
-- ROSIE_ROOT = ROSIE_HOME by default.  The user can override the default by setting the
-- environment variable $ROSIE_ROOT to point somewhere else.

ROSIE_ROOT = ROSIE_HOME

local ok, value = pcall(os.getenv, "ROSIE_ROOT")
if (not ok) then error('Internal error: call to os.getenv(ROSIE_ROOT)" failed'); end
if value then ROSIE_ROOT = value; end

-- All values are strings.
ROSIE_INFO = {
   {name="ROSIE_HOME",    value=ROSIE_HOME,                  desc="location of the rosie installation directory"},
   {name="ROSIE_VERSION", value=ROSIE_VERSION,               desc="version of rosie installed"},
   {name="ROSIE_DEV",     value=tostring(ROSIE_DEV),         desc="true if rosie was started in development mode"},
   {name="HOSTNAME",      value=os.getenv("HOSTNAME") or "", desc="host on which rosie is running"},
   {name="HOSTTYPE",      value=os.getenv("HOSTTYPE") or "", desc="type of host on which rosie is running"},
   {name="OSTYPE",        value=os.getenv("OSTYPE") or "",   desc="type of OS on which rosie is running"},
   {name="CWD",           value=os.getenv("PWD") or "",      desc="current working directory"},
   {name="ROSIE_COMMAND", value=ROSIE_COMMAND or "",         desc="invocation command, if rosie invoked through the CLI"}
}

----------------------------------------------------------------------------------------
-- Build the rosie module as seen by the Lua client
----------------------------------------------------------------------------------------
local file_functions = {
   match = process_input_file.match,
   eval = process_input_file.eval,
   grep = function(...) error("rosie.file.grep not implemented"); end
}

local rosie = {engine = engine, file = file_functions}

function rosie.info() return ROSIE_INFO; end

return rosie
