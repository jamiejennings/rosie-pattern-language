-- -*- Mode: Lua; -*-                                                                             
--
-- environment.lua    Rosie environments
--
-- © Copyright IBM Corporation 2017, 2018.
-- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
-- AUTHOR: Jamie A. Jennings

-- Environments can be extended in a way that new bindings shadow old ones.  This permits a tree
-- of environments that model nested scopes.  Currently, that nesting is used rarely.  Grammar
-- compilation uses this.
-- 
-- The root of an environment tree is the "base environment" for a package P.  For every other
-- package, X, that is open in P, there is a binding in P: X.prefix->X.env where X.prefix is the
-- prefix used for X in P, and X.env is the package environment for X.

local environment = {}

local common = require "common"
local ast = require "ast"
local recordtype = require "recordtype"
local lpeg = require "lpeg"
local list = require "list"
local builtins = require "builtins"

---------------------------------------------------------------------------------------------------

local env

local function lookup(env, id, prefix)
   assert(environment.is(env))
   assert(type(id)=="string")
   assert( (prefix==nil) or ((type(prefix)=="string") and (#prefix > 0)) )
   if prefix then
      local mod = lookup(env, prefix)
      if environment.is(mod) then
	 local val = lookup(mod, id)
	 if val and val.exported then		    -- we are duck typing here
	    return val
	 else
	    return nil
	 end
      else
	 return nil, prefix .. " is not a valid package reference"
      end
   else
      return env.store[id] or (env.parent and lookup(env.parent, id))
   end
end

local function bind(env, id, value)
   assert(environment.is(env))
   assert(type(id)=="string")
   env.store[id] = value
end

-- Use env:bind(id, nil) to remove a shallow binding, possibly exposing another binding for the
-- same identifier from an outer environment.
-- Use env:unbind(id) in an interactive setting to remove a binding no matter where it came from.
-- This may also expose a deeper binding for the same identifier, which can be removed with
-- another call to unbind().
-- Return values:
--    nil if id not found;
--    false if found (and unbound);
--    true if unbound but the unbinding exposed another binding for the same identifier
local function unbind(env, id)
   assert(environment.is(env))
   assert(type(id)=="string")
   while (not env.store[id]) and env.parent do
      env = env.parent
   end
   if not env.store[id] then return nil; end
   env.store[id] = nil
   return lookup(env, id) or false
end

env = recordtype.new("environment",
		     {store = recordtype.NIL,
		      parent = recordtype.NIL,
		      origin = recordtype.NIL,
		      exported = false,		    -- prevents export of modules
		      lookup = lookup,
		      bind = bind,
		      unbind = unbind,
		      bindings = function(self)
				    local current_env = self
				    return function(_, key)
					      local k, v = next(current_env.store, key)
					      if k then return k, v
					      else
						 while (not k) and (current_env.parent) do
						    current_env = current_env.parent
						    k, v = next(current_env.store)
						 end
						 if k then return k, v; end
					      end
					   end,
				    self,
				    nil
				 end,
		   },
		     function(parent)
			return env.factory{store={}, parent=parent}; end)

environment.PRELUDE_IMPORTPATH = assert(builtins.PRELUDE_IMPORTPATH)

function environment.make_standard_prelude()
   local e = env.new()
   e.store = builtins.make_standard_prelude_store()
   return e
end

function environment.get_builtin_package(importpath)
   local pkgname, store = builtins.get_package_store(importpath)
   if not pkgname then return false; end
   local e= env.new()
   e.store = store
   return pkgname, e
end

environment.is = env.is

environment.new = function (prelude)
		     if not prelude then
			return env.new()
		     elseif environment.is(prelude) then
			return env.new(prelude)
		     else
			error("invalid prelude argument to environment.new")
		     end
		  end

environment.extend = function (parent)
			if env.is(parent) then return env.new(parent); end
			error("extend environment called with arg that is not an environment: "
			      .. tostring(parent))
			end

function environment.exported_bindings(env)
   local tbl = {}
   for k,v in env:bindings() do
      if v.exported then tbl[k]=v; end
   end
   return tbl
end

function environment.all_bindings(env)
   local tbl = {}
   for k,v in env:bindings() do tbl[k]=v; end
   return tbl
end

-- -----------------------------------------------------------------------------
-- Module table (per engine)
-- -----------------------------------------------------------------------------

-- Each engine has a "global" package table that maps: importpath -> env
-- where env is the environment for the module, containing both local and exported bindings. 
function environment.new_package_table()
   local pkgtable = setmetatable({}, {__tostring = function(env) return "<package_table>"; end;})
   return pkgtable
end

return environment
