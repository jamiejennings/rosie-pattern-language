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
-- Environment functions and initial environment
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
	   
-- Base environment, which can be extended with new_env, but not written to directly,
-- because it is shared between match engines:

local default_pkg = "."

local ENV =
   {[default_pkg] = 
    {[dot_id] = pattern.new{name=dot_id; peg=utf8_char_peg; alias=true; raw=true};  -- any single character
     [eol_id] = pattern.new{name=eol_id; peg=lpeg.P(-1); alias=true; raw=true}; -- end of input
     [b_id] = pattern.new{name=b_id; peg=boundary; alias=true; raw=true}; -- token boundary
  }
}
	      
setmetatable(ENV, {__tostring = function(env)
				   return "<base environment>"
				end;
		   __newindex = function(env, key, value)
				   error('Compiler: base environment is read-only, '
					 .. 'cannot assign "' .. key .. '"')
				end;
		})

function environment.new(base_env)
   local env = {[default_pkg]={}}
   base_env = base_env or ENV
   setmetatable(env[default_pkg], {__index = base_env[default_pkg]})
   setmetatable(env, {__index = function(...) error("Internal error (get): env impl not a table") end,
		      __newindex = function(...) error("Internal error (set): env impl not a table") end,
		      __tostring = function(env) return "<environment>"; end;})
   return env
end

local function lookup(env, id, prefix)
   assert(prefix==nil)				    -- !@# TEMPORARY
   return env[default_pkg][id]
end

environment.lookup = lookup

local function bind(env, id, value)
   env[default_pkg][id] = value
end

environment.bind = bind

-- return a flat representation of env (recall that environments are nested)
function environment.flatten(env, output_table)
   if not output_table then
      assert(env[default_pkg], "not a proper environment")	    -- !@# TEMPORARY
      env = env[default_pkg]					    -- !@# TEMPORARY
      output_table = {}
   end
   for item, value in pairs(env) do
      -- if already seen, do not overwrite with value from parent env
      if not output_table[item] then output_table[item] = value; end
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
