---- -*- Mode: Lua; -*- 
----
---- syntax.lua   syntactic transformations (AST -> AST)
----
---- (c) 2016, Jamie A. Jennings
----

local common = require "common"			    -- AST functions
local compile = require "compile"
local cinternals = compile.cinternals

-- !@# Eliminate subidx because it's always 1!

-- Add to the Emacs command 'rosie' a memo of last rosie home dir used.

-- Add a field to pattern record for "original_ast" where we can store the pre-transformation ast.


--local
   boundary_ast = cinternals.ENV[common.boundary_identifier].ast

function cooked_to_raw(a)
   local name, pos, text, subs, subidx = common.decode_match(a)
   assert(name == "cooked")
   assert((#subs - subidx + 1) == 1)
   local exp = subs[subidx]
   if next(exp)=="sequence" then
      local name, pos, text, subs, subidx = common.decode_match(exp)
      assert((#subs - subidx + 1) == 2)		    -- two branches in a sequence
      local type1 = next(subs[subidx])
      if type1=="negation" or type1=="lookat" then
	 return a				    -- nothing to do
      else
	 -- make the new tree here
	 -- !@# What to do with pos and text fields???
	 return common.create_match("raw",
				    pos,
				    text,
				    subs[1],
				    boundary_ast,
				    subs[2]
				 )
      end
--   elseif next(exp)== ... then -- what else needs transformation?
   end			       -- switch on type of a
end





