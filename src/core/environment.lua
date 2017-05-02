-- -*- Mode: Lua; -*-                                                                             
--
-- environment.lua    Rosie environments
--
-- © Copyright IBM Corporation 2017.
-- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
-- AUTHOR: Jamie A. Jennings



local environment = {}

local common = require "common"
local pattern = common.pattern
local lpeg = require "lpeg"
local locale = lpeg.locale()

---------------------------------------------------------------------------------------------------
-- Items for the initial environment
---------------------------------------------------------------------------------------------------

local b_id = common.boundary_identifier
local dot_id = common.any_char_identifier
local eol_id = common.end_of_input_identifier

----------------------------------------------------------------------------------------
-- Boundary for tokenization... this is going to be customizable, but hard-coded for now
----------------------------------------------------------------------------------------

local boundary = locale.space^1 + #locale.punct
              + (lpeg.B(locale.punct) * #(-locale.punct))
	      + (lpeg.B(locale.space) * #(-locale.space))
	      + lpeg.P(-1)
	      + (- lpeg.B(1))

environment.boundary = boundary
local utf8_char_peg = common.utf8_char_peg
	   
-- The base environment is ENV, which can be extended with new_env, but not written to directly,
-- because it is shared between match engines.  Eventually, it will be replaced by a "standard
-- prelude", a la Haskell.  :-)

local ENV =
    {[dot_id] = pattern.new{name=dot_id; peg=utf8_char_peg; alias=true; raw=true};  -- any single character
     [eol_id] = pattern.new{name=eol_id; peg=lpeg.P(-1); alias=true; raw=true}; -- end of input
     [b_id] = pattern.new{name=b_id; peg=boundary; alias=true; raw=true}; -- token boundary
  }
	      
setmetatable(ENV, {__tostring = function(env)
				   return "<base environment>"
				end;
		   __newindex = function(env, key, value)
				   error('Compiler: base environment is read-only, '
					 .. 'cannot assign "' .. key .. '"')
				end;
		})


-- Each engine has a "global" module table that maps: importpath -> env
-- where env is the environment for the module, containing both local and exported bindings. 
function environment.make_module_table()
   return setmetatable({}, {__tostring = function(env) return "<module_table>"; end;})
end

local OPENMODULES = 1

-- Environments can be extended in a way that new bindings shadow old ones.  This permits a tree
-- of environments that model nested scopes.  Currently, that nesting is used rarely.  Grammar
-- compilation uses this.
-- 
-- The root of an environment tree is the "base environment" for a module M.  For each other
-- module, X, open in M, the OPENMODULES table maps the prefix for X to the module environment for
-- X.

function environment.new()
   local env = environment.extend(ENV)
   env[OPENMODULES]={}
   return env
end

function environment.extend(parent_env)
   return setmetatable({}, {__index = parent_env,
			    __tostring = function(env) return "<environment>"; end;})
end

local function lookup(env, id, prefix)
   assert(prefix==nil)				    -- !@# TEMPORARY
   return env[id]
end

environment.lookup = lookup

local function bind(env, id, value)
   env[id] = value
end

environment.bind = bind

-- return a flat representation of env (recall that environments are nested)
function environment.flatten(env, output_table)
   output_table = output_table or {}
   for item, value in pairs(env) do
      -- access only string keys.  numeric keys are for other things.
      if type(item)=="string" then
	 -- if already seen, do not overwrite with value from parent env
	 if not output_table[item] then output_table[item] = value; end
      end
   end
   local mt = getmetatable(env)
   if mt and type(mt.__index)=="table" then
      -- there is a parent environment
      return environment.flatten(mt.__index, output_table)
   else
      return output_table
   end
end

return environment
