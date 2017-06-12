-- -*- Mode: Lua; -*-                                                                             
--
-- expand.lua    RPL macro expansion
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

local expand = {}

local ast = require "ast"
local list = require "list"
local environment = require "environment"
local lookup = environment.lookup
local bind = environment.bind


-- The ambient "atmosphere" in rpl is that sequences are cooked unless explicitly marked as raw.
-- 'ambient_cook' wraps the rhs of bindings in an explicit 'cooked' ast unless the expression is
-- already explicitly cooked or raw.  Each statement in the list is side-effected, replacing its
-- 'exp' field.
local function ambient_cook(stmts)
   for _, stmt in ipairs(stmts) do
      if not (ast.raw.is(stmt.exp) or ast.cooked.is(stmt.exp)) then
	 stmt.exp = ast.cooked.new{exp=stmt.exp, s=0, e=0} -- s=stmt.exp.s, e=stmt.exp.e
      end
   end -- for
end

local boundary_ref = ast.ref.new{localname=common.boundary_identifier}

local ambient_cook_exp

local function ambient_raw_exp(ex)
   if ast.cooked.is(ex) then return ambient_cook_exp(ex.exp)
   elseif ast.raw.is(ex) then return ambient_raw_exp(ex.exp)
   elseif ast.sequence.is(ex) then
      -- do not introduce boundary references between the exps
      return ast.sequence.new{exps=map(ambient_cook_exp, ex.exps), s=ex.s, e=ex.e}
   elseif ast.predicate.is(ex) or
          ast.choice.is(ex) or
          ast.grammar.is(ex) or
          ast.repetition.is(ex) then
      -- the explicit 'raw' construct has no effect on these exps, but they have sub-expressions
      -- that must be processed
      return ambient_cook_exp(ex)
   else
      -- finally, return expressions that do not have sub-expressions to process
      return ex
   end
end

-- The compiler does not know about cooked/raw expressions.  Both ast.cooked and ast.raw
-- structures are removed here, where we implement the notion that the ambience is, by default,
-- "cooked".
function ambient_cook_exp(ex)
   if ast.cooked.is(ex) then return ambient_cook_exp(ex.exp)
   elseif ast.raw.is(ex) then return ambient_raw_exp(ex.exp)
   elseif ast.predicate.is(ex) then
      return ast.predicate.new{type=ex.type, exp=ambient_cook_exp(ex.exp), s=ex.s, e=ex.e}
   elseif ast.choice.is(ex) then
      return ast.choice.new{exps=map(ambient_cook_exp, ex.exps), s=ex.s, e=ex.e}
   elseif ast.sequence.is(ex) then
      local exps = map(ambient_cook_exp, ex.exps)
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
      return ast.grammar.new{rules=ambient_cook_exp(ex.rules), s=ex.s, e=ex.e}
   elseif ast.repetition.is(ex) then 
      -- ambience has no effect on a repetition, but the expression being repeated must be
      -- carefully transformed: if it explicitly cooked, then flag the repetition as cooked, strip
      -- the 'cooked' ast off the exp being repeated and treat what is inside the 'cooked' ast as
      -- if it were raw; if not explicitly cooked, then treat ex.exp it as if it is raw.
      local flag = ast.cooked.is(ex.exp)
      local new = (flag and ambient_raw_exp(ex.exp.exp)) or ambient_raw_exp(ex.exp)
      return ast.repetition.new{exp=new, cooked=flag, max=ex.max, min=ex.min, s=ex.s, e=ex.e}
   else
      -- There are no sub-expressions to process in the rest of the expression types, such as
      -- refs, literals, and character set expressions.
      return ex
   end -- switch on kind of ex
end

local function remove_cooked_raw(stmts)
   for _, stmt in ipairs(stmts) do
      stmt.exp = ambient_cook_exp(stmt.exp)
   end
end

-- Process macro-expansions, which are encoded in the ast as applications.  Note that not all
-- applications are macros.  Some may be functions.  It is intentionally reminiscent of Scheme
-- that (1) macro use looks syntactically like function application, (2) there is a single
-- namespace for macros, functions, and other values, and (3) macro expansion requires a syntactic
-- environment in which (at least) references to macros can be resolved.
function expand.expression(ex, env, messages)
   -- TODO
   return ex
end

function expand.stmts(stmts, env, messages)
   for _, stmt in ipairs(stmts) do
      assert(ast.binding.is(stmt))
      local ref = stmt.ref
      print("*** calling dummy expand.expression for " ..
	    (ref.packagename and (ref.packagename .. ".") or "") ..
	    ref.localname ..
	    " = " ..
	    tostring(stmt.exp))
      stmt.exp = expand.expression(stmt.exp, env, messages)
   end
end

function expand.block(a, env, messages)
   assert(ast.block.is(a))
   assert(environment.is(env))
   assert(type(messages)=="table")

   -- TODO: Need a version of ambient_cook_exp and remove_cooked_raw that operate directly on expressions!

   ambient_cook(a.stmts)
   remove_cooked_raw(a.stmts)
   expand.stmts(a.stmts, env, messages)
   return true
end




return expand

