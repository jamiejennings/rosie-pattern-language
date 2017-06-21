-- -*- Mode: Lua; -*-                                                                             
--
-- environment.lua    Rosie environments
--
-- © Copyright IBM Corporation 2017.
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
local pattern = common.pattern
local macro = common.macro
local pfunction = common.pfunction
local recordtype = require "recordtype"
local lpeg = require "lpeg"
local locale = lpeg.locale()

---------------------------------------------------------------------------------------------------
-- Items for the initial environment
---------------------------------------------------------------------------------------------------

local b_id = common.boundary_identifier
local dot_id = common.any_char_identifier
local eol_id = common.end_of_input_identifier

local function pfunction_find(...)
   local args = {...}
   if #args~=1 then error("find takes one argument, " .. tostring(#args) .. " given"); end
   local ast = args[1]
   assert(ast.type=="rpl_expression")
   -- First we make sure that the argument actually compiles
--   local pat, msgs = compile(nil, ast, en._modtable, env)
--   if not pat then return false, msgs; end
   local replacement = ast.subs[1]
   -- Next, transform pat.ast
   local ast, orig_ast = parse("{{!e .}* e}+")

   

   assert(type(ast)=="table" and ast.subs and ast.subs[1] and (not ast.subs[2]))
   assert(ast.type=="rpl_expression")
   assert(ast.subs[1].type=="raw_exp", "type is: " .. ast.subs[1].type)
   ast = ast.subs[1]
   assert(ast.subs and ast.subs[1])
   local template = ast.subs[1]
   local grep_ast = syntax.replace_ref(template, "e", replacement)
   assert(type(grep_ast)=="table", "syntax.replace_ref failed")
   grep_ast = common.create_match("rpl_expression", 1, "search:(" .. pattern_exp .. ")", grep_ast)


end   

local function example_first(...)
   io.write("*** example_first called with args: ")
   local args = {...}
   for _, arg in ipairs(args) do
      io.write(tostring(arg), " ")
   end
   print("***")
   return args[1]
end

local function example_last(...)
   io.write("*** example_last called with args: ")
   local args = {...}
   for _, arg in ipairs(args) do
      io.write(tostring(arg), " ")
   end
   print("***")
   return args[#args]
end

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
--     ["find"] = macro.new{primop=pfunction_find};
     ["last"] = macro.new{primop=example_last};
     ["first"] = macro.new{primop=example_first};
  }
	      
setmetatable(ENV, {__tostring = function(env)
				   return "<base environment>"
				end;
		   __newindex = function(env, key, value)
				   error('Compiler: base environment is read-only, '
					 .. 'cannot assign "' .. key .. '"')
				end;
		})



-- Each engine has a "global" package table that maps: importpath -> env
-- where env is the environment for the module, containing both local and exported bindings. 
function environment.make_module_table()
   return setmetatable({}, {__tostring = function(env) return "<module_table>"; end;})
end

local env					    -- forward ref for env.factory
env = recordtype.new("environment",
		     {store = recordtype.NIL,
		      parent = recordtype.NIL,
		      exported = false,
		      next = function(self, key)
				return next(self.store, key)
			     end,
		      bindings = function(self)
				    return function(store, key)
					      return next(store, key)
					   end,
				    self.store,
				    nil
				 end,
		   },
		     function(parent)
			return env.factory{store={}, parent=parent}; end)

local base_environment = env.new(); base_environment.store = ENV

environment.new = function (...)
		     if #{...}==0 then return env.new(base_environment); end
		     error("new environment called with arg(s)")
		  end

environment.extend = function (parent)
			if env.is(parent) then return env.new(parent); end
			error("extend environment called with arg that is not an environment: "
			      .. tostring(parent))
			end

environment.is = env.is

function environment.lookup(env, id, prefix)
   assert(environment.is(env))
   if prefix then
      local mod = environment.lookup(env, prefix)
      if environment.is(mod) then
	 local val = environment.lookup(mod, id)
	 if val and val.exported then		    -- hmmm, we are duck typing here
	    return val
	 else
	    return nil
	 end
      else -- found prefix but it is not a module
	 return nil, prefix .. " is not a valid module reference"
      end
   else
      -- no prefix
      return env.store[id] or (env.parent and environment.lookup(env.parent, id))
   end
end

-- N.B. value can be nil (this is how bindings are removed)
function environment.bind(env, id, value)
   assert(environment.is(env))
   assert(type(id)=="string")
   env.store[id] = value
end

-- return a flat representation of env (recall that environments are nested)
function environment.flatten(env, output_table)
   output_table = output_table or {}
   for item, value in pairs(env.store) do
      -- access only string keys.  numeric keys are for other things.
      if type(item)=="string" then
	 -- if already seen, do not overwrite with value from parent env
	 if not output_table[item] then output_table[item] = value; end
      end
   end
   if env.parent then
      return environment.flatten(env.parent, output_table)
   else
      return output_table
   end
end

return environment
