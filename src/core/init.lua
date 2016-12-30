---- -*- Mode: Lua; -*-                                                                           
----
---- init.lua    Load the Rosie system, given the location of the installation directory
----
---- © Copyright IBM Corporation 2016.
---- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
---- AUTHOR: Jamie A. Jennings

-- rosie.lua:
--   Usage: rosie = require "rosie"
--   The Rosie installation (Makefile) will create rosie.lua that looks like this:
--
--   return dofile\("/Users/jjennings/Work/Dev/public/rosie-pattern-language/src/core/init.lua"\)
-- 

-- Current lapi functions, sorted by where they will end up:
--
-- rosie.info()
--   home: "/Users/jjennings/Work/Dev/public/rosie-p...", 
--
-- rosie.engine.new(optional_name)
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
-- engine:env(optional_identifier)
--   get_environment: function: 0x7fc58cd1a640, 
--
-- engine:clear(optional_identifier)
--   clear_environment: function: 0x7fc58cd19660, 
--
-- engine:id()
-- engine:name(optional_name)
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

BOOTSTRAP_COMPLETE = false;

-- When init is loaded from rosie.lua, ROSIE_DEV will be unset.
-- When init is loaded from run-rosie, ROSIE_DEV will always be true or false 
if ROSIE_DEV==nil then ROSIE_DEV=true; end

local loader, msg = loadfile(ROSIE_HOME .. "/src/load-modules.lua", "t", _ENV)
if not loader then error("Error while initializing: " .. msg); end
loader()

-- During bootstrapping, we have to compile the rpl using the "core" compiler, and
-- manually configure ROSIE_ENGINE without calling engine_configure.
-- To bootstrap, we have to compile the Rosie rpl using the core parser/compiler
-- Create a matching engine for processing Rosie Pattern Language files

load_module("rpl-parser")

ROSIE_ENGINE = engine.new("RPL engine")
compile.compile_core(ROSIE_HOME.."/src/rpl-core.rpl", ROSIE_ENGINE.env)
local success, result = compile.compile_match_expression('rpl', ROSIE_ENGINE.env)
if not success then error("Bootstrap error: could not compile rosie core rpl: " .. tostring(result)); end

ROSIE_ENGINE.expression = 'rpl';
ROSIE_ENGINE.pattern = success;
ROSIE_ENGINE.encode = "null/bootstrap";
ROSIE_ENGINE.encode_function = function(m) return m; end;

-- Install the new parser.
compile.set_parser(parse_and_explain);

-- The value of ROSIE_HOME on entry to this file is set by either:
-- (1) The shell script bin/rosie, which was
--      - created by the Rosie installation process (Makefile), to include the value
--        of ROSIE_HOME. 
--      - When that script is invoked by the user in order to run Rosie,
--        the script passes ROSIE_HOME to cli.lua, which has called this file (init).
-- Or (2) The code in rosie.lua, which was also created by the Rosie installation.
--
-- The location of the Rosie standard library (of patterns) is ROSIE_ROOT/rpl.
-- And compiled Rosie packages are stored in ROSIE_ROOT/pkg.
--
-- ROSIE_ROOT = ROSIE_HOME by default.  The user can override the default by setting the
-- environment variable $ROSIE_ROOT to point somewhere else.

ROSIE_ROOT = ROSIE_HOME

local ok, value = pcall(os.getenv, "ROSIE_ROOT")
if (not ok) then error('Internal error: call to os.getenv(ROSIE_ROOT)" failed'); end
if value then ROSIE_ROOT = value; end

BOOTSTRAP_COMPLETE = true


print("\nContents of rosie:")
for k,v in pairs(_ENV) do print(k,v); end; print()


return _ENV
