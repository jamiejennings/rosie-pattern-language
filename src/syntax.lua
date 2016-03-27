---- -*- Mode: Lua; -*- 
----
---- syntax.lua   syntactic transformations (AST -> AST)
----
---- (c) 2016, Jamie A. Jennings
----

local common = require "common"			    -- AST functions
<<<<<<< cb95397849351065999992fc06d4bc060c1ae601
--local compile = require "compile"
--local cinternals = compile.cinternals

-- !@# Eliminate subidx because it's always 1!

-- Add to the Emacs command 'rosie':
   -- switch to rosie buffer if it exists
   -- memo of last rosie home dir used, if need to start rosie

-- Add a field to pattern record for "original_ast" where we can store the pre-transformation ast.


--local boundary_ast = cinternals.ENV[common.boundary_identifier].ast
local boundary_ast = common.create_match("identifier", 0, common.boundary_identifier)

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
	 return a				    -- copy of?
      else
	 -- make the new tree here
	 -- !@# What to do with pos and text fields???
	 return common.create_match("raw",
				    0,		    -- pos
				    "",		    -- text
				    common.create_match("sequence",
							0,
							"",
							subs[1], -- copy of?
							common.create_match("sequence",
									    0,
									    "",
									    boundary_ast,   -- copy of?
									    subs[2]	    -- copy of?
									 )))
      end
   elseif next(exp)=="raw" then
      return a					    -- copy of?
   elseif next(exp)=="quantified_exp" then
      local e = subs[subidx]
      local q = subs[subidx+1]
      local type1 = next(e)
      if type1=="raw" or
	 type1=="charset" or
	 type1=="named_charset" or
	 type1=="string" or
	 type1=="identifier" then
	 return macro_expand(a)			    -- !@#
      else

	 -- Compiling quantified expressions is subtle when Rosie is tokenizing, i.e. in "cooked" mode.
	 --    With a naive approach, this expression will always fail to recognize more than one word:
	 --                    (","? word)*
	 --    The reason is that the repetition ends up looking for the token boundary TWICE when the ","?
	 --    fails.  And (in the absence of punctuation) since the token boundary consumes all whitespace
	 --    (and must consume something), the second attempt to match boundary will fail because the
	 --    prior attempt consumed all the whitespace.
	 -- 
	 --    Here's the solution:
	 --      Consider e*, e?, and e{0,m} where m>0.  Call these expressions qe.  When we
	 --      have a sequence of qe followed by f, what we want to happen in cooked mode is
	 --      this:
	 --        match('qe f', "e f") -> match
	 --        match('qe f', " f") -> no match, strictly speaking
	 --        match('qe f', "f") -> match
	 --      I.e. 'e* f' should work like '<e+ boundary f> / f'
	 --           'e? f' should work like '<e boundary f> / f'
	 --           'e{0,m} f' should work like '<e{1,m} boundary f> / f'
	 --      And these can be rewritten as:
	 --           '<e+ boundary f> / f'      -->  < <e+ boundary>? f >
	 --           '<e boundary f> / f'       -->  < <e boundary>? f >
	 --           '<e{1,m} boundary f> / f'  -->  < <e{1,m} boundary>? f >
	 --      Conclusion: In cooked mode, quantified expressions like qe should compile as:
	 --         e*     --> <e+ boundary>?
	 --         e?     --> <e boundary>?
	 --         e{0,m} --> <e{1,m} boundary>?
	 --      Of course, the boundary is only necessary when qe appears in the context of a
	 --      sequence, with terms coming after it.  Are there edge cases where it might be
	 --      important to match qe without a boundary following it always?  Can't think of any (noting
	 --      that the end of input is not an issue because boundary checks for that).

	 local qname, qpos, qtext, qsubs, qsubidx = common.decode_match(q)

	 e = macro_expand(e)

	 if qname=="plus" then
	    -- a => {e boundary}+
	 elseif qname=="star" then
	    -- a => {{e boundary}+}?                                 -- yep.
	 elseif qname=="question" then
	    -- a => {e boundary}?
	 elseif qname=="repetition" then
	    assert(type(qsubs[qsubidx])=="table")
	    assert(qsubs[qsubidx], "not getting min clause in cooked_to_raw")
	    local mname, mpos, mtext = common.decode_match(qsubs[qsubidx])
	    assert(mname=="low")
	    min = tonumber(mtext) or 0
	    assert(qsubs[qsubidx+1], "not getting max clause in cooked_to_raw")
	    local mname, mpos, mtext = common.decode_match(qsubs[qsubidx+1])
	    max = tonumber(mtext)
	    if (min < 0) or (max and (max < 0)) or (max and (max < min)) then
	       explain_repetition_error(a, source)
	    end
	    if (not max) then
	       if (min == 0) then
		  -- same as star
		  -- a => {{e boundary}+}?
	       else
		  -- min > 0 due to prior checking
		  assert(min > 0)
		  -- a => {e boundary}{min,}
	       end
	    else
	       -- here's where things get interesting, because we must see at least min copies of e,
	       -- and at most max.
	       a = {}				    -- empty AST
	       for i=1,min do
		  -- a = {a {e boundary}}
	       end -- for
	       if (min-max) < 0 then
		  -- a = {a {e boundary}{,max-min}
	       else
		  assert(min==max)
	       end
	       -- finally, here's the check for "and not looking at another copy of e"
	       -- a = {a {! a}}
	    end -- if not max
	 else					    -- switch on quantifier type
	    explain_unknown_quantifier(a, source)
	 end -- switch on quantifier type
      end -- whether we need to modify a or not

      --   elseif next(exp)== ... then -- what else needs transformation?
   end			       -- switch on type of a
end





