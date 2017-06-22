-- -*- Mode: Lua; -*-                                                                             
--
-- e2.lua    RPL macro expansion that goes with the p2 parser and the c2 compiler
--           When you see "e2", read it as "expand", e.g. "e2.stmts" == "expand statements"
--
-- © Copyright IBM Corporation 2017.
-- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
-- AUTHOR: Jamie A. Jennings

-- Syntax expansion is interleaved with the reification of modules as packages.  See loadpkg to
-- see how the code below is invoked.  The process is roughly this:
--
--    parse --> convert to ast --> instantiate dependencies --> syntax expand --> compile
-- 
-- Syntax expansion steps for a 'binding':
--   1. Introduce explicit cooked groups where they are implied, e.g. rhs of assignments
--   2. Expand the expression on the right hand side
-- 
-- Syntax expansion steps for an expression:
--   1. Apply user-defined and built-in macro expansions
--   2. Remove cooked groups by interleaving references to the boundary identifier, ~.

local e2 = {}

local ast = require "ast"
local list = require "list"
local environment = require "environment"
local lookup = environment.lookup
local bind = environment.bind
local common = require "common"
local pfunction = common.pfunction
local macro = common.macro

-- The ambient "atmosphere" in rpl is that sequences are cooked unless explicitly marked as raw.
-- 'ambient_cook' wraps the rhs of bindings in an explicit 'cooked' ast unless the expression is
-- already explicitly cooked or raw.  Each statement in the list is side-effected, replacing its
-- 'exp' field.
local function ambient_cook_exp(ex)
   if not (ast.raw.is(ex) or ast.cooked.is(ex)) then
      return ast.cooked.new{exp=ex, s=0, e=0}
   end
end

local boundary_ref = ast.ref.new{localname=common.boundary_identifier}

local remove_cooked_exp;

local function remove_raw_exp(ex)
   if ast.cooked.is(ex) then return remove_cooked_exp(ex.exp)
   elseif ast.raw.is(ex) then return remove_raw_exp(ex.exp)
   elseif ast.predicate.is(ex) then
      return ast.predicate.new{type=ex.type, exp=remove_raw_exp(ex.exp), s=ex.s, e=ex.e}
   elseif ast.choice.is(ex) then
      return ast.choice.new{exps=map(remove_raw_exp, ex.exps), s=ex.s, e=ex.e}
   elseif ast.sequence.is(ex) then
      -- do not introduce boundary references between the exps
      local exps = map(remove_raw_exp, ex.exps)
      assert(#exps > 0, "received an empty sequence")
      return ast.sequence.new{exps=exps, s=ex.s, e=ex.e}
   elseif ast.repetition.is(ex) then 
      local flag = ast.cooked.is(ex.exp)
      local new = remove_raw_exp(ex.exp)
      return ast.repetition.new{exp=new, cooked=flag, max=ex.max, min=ex.min, s=ex.s, e=ex.e}
   elseif ast.grammar.is(ex) then
      -- An explicit 'raw' syntax cannot appear around a grammar in the current syntax
      assert(false, "rpl 1.1 grammar should not allow raw syntax surrounding a grammar")
   else
      -- finally, return expressions that do not have sub-expressions to process
      return ex
   end
end

local remove_cooked_raw_from_stmts;

-- The compiler does not know about cooked/raw expressions.  Both ast.cooked and ast.raw
-- structures are removed here, where we implement the notion that the ambience is, by default,
-- "cooked".
function remove_cooked_exp(ex)
   if ast.cooked.is(ex) then return remove_cooked_exp(ex.exp)
   elseif ast.raw.is(ex) then return remove_raw_exp(ex.exp)
   elseif ast.predicate.is(ex) then
      return ast.predicate.new{type=ex.type, exp=remove_cooked_exp(ex.exp), s=ex.s, e=ex.e}
   elseif ast.choice.is(ex) then
      return ast.choice.new{exps=map(remove_cooked_exp, ex.exps), s=ex.s, e=ex.e}
   elseif ast.sequence.is(ex) then
      local exps = map(remove_cooked_exp, ex.exps)
      assert(#exps > 0, "received an empty sequence")
      local new = list.new(exps[1])
      for i = 2, #exps do
	 if not ast.predicate.is(exps[i-1]) then
	    -- boundary references inserted after any exp EXCEPT a predicate
	    table.insert(new, boundary_ref)
	 end
	 table.insert(new, exps[i])
      end -- for
      return ast.sequence.new{exps=new, s=ex.s, e=ex.e}
   elseif ast.grammar.is(ex) then
      -- ambience has no effect on a grammar expression
      remove_cooked_raw_from_stmts(ex.rules) 
      return ex
   elseif ast.repetition.is(ex) then 
      -- ambience has no effect on a repetition, but the expression being repeated must be
      -- carefully transformed: if it explicitly cooked, then flag the repetition as cooked, strip
      -- the 'cooked' ast off the exp being repeated and treat what is inside the 'cooked' ast as
      -- if it were raw; if not explicitly cooked, then treat ex.exp it as if it is raw.
      local flag = ast.cooked.is(ex.exp)
      local new = remove_raw_exp(ex.exp)
      return ast.repetition.new{exp=new, cooked=flag, max=ex.max, min=ex.min, s=ex.s, e=ex.e}
   else
      -- There are no sub-expressions to process in the rest of the expression types, such as
      -- refs, literals, and character set expressions.
      return ex
   end -- switch on kind of ex
end

local remove_cooked_raw_from_exp = remove_cooked_exp;

function remove_cooked_raw_from_stmts(stmts)
   for _, stmt in ipairs(stmts) do
      stmt.exp = remove_cooked_raw_from_exp(stmt.exp)
   end
end

local apply_macros;

local function apply_macro(ex, env, messages)
   assert(ast.application.is(ex))
   assert(ast.ref.is(ex.ref))
   local m = environment.lookup(env, ex.ref.localname, ex.ref.packagename)
   local refname = ex.ref.packagename and (ex.ref.packagename .. ".") or ""
   refname = refname .. ex.ref.localname
   if not m then
      violation.throw(violation.compile.new{who='macro expander',
					    message='undefined operator: ' .. refname,
					    ast=ex})
   elseif pfunction.is(m) then
      return ex				    -- pfunctions applied later
   elseif not macro.is(m) then
      local msg = 'type mismatch: ' .. refname .. " is not a macro/function"
      violation.throw(violation.compile.new{who='macro expander',
					    message=msg,
					    ast=ex})
   end
   -- Have a macro to expand!
   if not m.primop then
      assert(false, "user-defined macros are currently not supported")
   end
   common.note("applying built-in macro '" .. refname .. "'")
   local ok, new = pcall(list.apply,
			 m.primop,
			 map(function(arg)
				return apply_macros(arg, env, messages)
			     end,
			     ex.arglist))
   if not ok then
      local msg = "error while expanding macro '" .. refname .. "': "
      msg = msg .. tostring(new)		    -- 'new' is the lua error
      violation.throw(violation.compile.new{who='macro expander',
					    message=msg,
					    ast=ex})
   end
   return new
end
   
function apply_macros(ex, env, messages)
   local map_apply_macros = function(exp)
			       return apply_macros(exp, env, messages)
			    end
   if ast.application.is(ex) then
      return apply_macro(ex, env, messages)
   elseif ast.cooked.is(ex) then
      return ast.cooked.new{exp=apply_macros(ex.exp, env, messages),
			    s=ex.s, e=ex.e}
   elseif ast.raw.is(ex) then
      return ast.raw.new{exp=apply_macros(ex.exp, env, messages),
		         s=ex.s, e=ex.e}
   elseif ast.sequence.is(ex) then
      return ast.sequence.new{exps=map(map_apply_macros, ex.exps),
			      s=ex.s, e=ex.e}
   elseif ast.choice.is(ex) then
      return ast.choice.new{exps=map(map_apply_macros, ex.exps),
			    s=ex.s, e=ex.e}
   elseif ast.predicate.is(ex) then
      return ast.predicate.new{type=ex.type, exp=apply_macros(ex.exp, env, messages),
			       s=ex.s, e=ex.e}
   elseif ast.repetition.is(ex) then 
      return ast.repetition.new{exp=apply_macros(ex.exp, env, messages),
			        cooked=ex.cooked, max=ex.max, min=ex.min, s=ex.s, e=ex.e}
   elseif ast.grammar.is(ex) then
      local newrules = {}
      local new
      for _, rule in ipairs(ex.rules) do
	 assert(ast.binding.is(rule))
	 -- N.B. If in future we ever allow macro definitions within a grammar, then the 'env'
	 -- passed to apply_macros below will have to be the grammar environment.
	 new = ast.binding.new{ref=rule.ref,
			       exp=apply_macros(rule.exp, env, messages),
			       is_alias=rule.is_alias,
			       is_local=rule.is_local,
			       s=rule.s, e=rule.e}
	 table.insert(newrules, new)
      end -- for
      return ast.grammar.new{rules=newrules, s=ex.s, e=ex.e}
   else
      -- finally, return expressions that do not have sub-expressions to process
      return ex
   end
end
   
-- Process macro-expansions, which are encoded in the ast as applications.  Note that not all
-- applications are macros.  Some may be functions.  It is intentionally reminiscent of Scheme
-- that (1) macro use looks syntactically like function application, (2) there is a single
-- namespace for macros, functions, and other values, and (3) macro expansion requires a syntactic
-- environment in which (at least) references to macros can be resolved.
local function expression(ex, env, messages)
   local cooked = ambient_cook_exp(ex)
   if cooked then ex = cooked; end

   -- Now we have an ast that a user should recognize as a parsing of their rpl source code, with
   -- the minor addition of a 'cooked' wrapper which makes the ambient/default mode of 'cooked'
   -- explicit.

   -- So we now pass the ast to any macros for expansion.  The resulting ast is then checked for
   -- validity and then further processed before compilation.

   ex = apply_macros(ex, env, messages)
   -- TODO: check for validity here


   -- The final steps in processing the ast are purely syntactic.  Here, we simplify the ast to
   -- transform some constructs, like raw/cooked, which are unknown to the compiler.  Such
   -- constructs are, of course, transformed into lower-level operations that the compiler does
   -- know about.
   ex = remove_cooked_raw_from_exp(ex)
   return ex
end

local function statements(stmts, env, messages)
   for _, stmt in ipairs(stmts) do
      assert(ast.binding.is(stmt))
      local ref = stmt.ref
      common.note("expanding " ..
		  (ref.packagename and (ref.packagename .. ".") or "") ..
	       ref.localname ..
	       " = " ..
	       tostring(stmt.exp))
      stmt.exp = expression(stmt.exp, env, messages)
   end
   return true
end

function e2.expression(ex, env, messages)
   local ok, result, err = violation.catch(expression, ex, env, messages)
   if not ok then error("Internal error in e2: " .. tostring(result)); end
   if not result then table.insert(messages, err); end
   return result				    -- if false, errors in messages tables
end

function e2.stmts(stmts, env, messages)
   local ok, result, err = violation.catch(statements, stmts, env, messages)
   if not ok then error("Internal error in e2: " .. tostring(result)); end
   if not result then table.insert(messages, err); end
   return result				    -- if false, errors in messages tables
end   


function e2.block(a, env, messages)
   assert(ast.block.is(a))
   assert(environment.is(env))
   assert(type(messages)=="table")
   local ok, result, err = violation.catch(statements, a.stmts, env, messages)
   if not ok then error("Internal error in e2: " .. tostring(result)); end
   if not result then table.insert(messages, err); end
   return result				    -- if false, errors in messages tables
end

return e2

