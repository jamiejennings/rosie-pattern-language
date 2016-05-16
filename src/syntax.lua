---- -*- Mode: Lua; -*- 
----
---- syntax.lua   syntactic transformations (AST -> AST)
----
---- (c) 2016, Jamie A. Jennings
----

local common = require "common"			    -- AST functions
require "list"

-- common.create_match("cooked", 1, "(...)", a)

local boundary_ast = common.create_match("identifier", 0, common.boundary_identifier)

-- local looking_at_boundary_ast = common.create_match("lookat", 0, "@/generated/", boundary_ast)
-- function cinternals.append_boundary(a)
--    return common.create_match("sequence", 1, "/generated/", a, looking_at_boundary_ast)
-- end
   
function validate(ast)
   if type(ast)~="table" then
      return false, "ast not a table";
   end
   local name, body = next(ast)
   if next(ast, name) then
      return false, "multiple names";
   elseif type(name)~="string" then
      return false, "non-string name";
   elseif type(body)~="table" then
      return false, "non-table body";
   else
      local function err(msg)
	 error("Invalid AST " .. name .. ": " .. msg)
      end
      for k,v in pairs(body) do
	 if type(k)~="string" then return err("non-string key in body");
	 elseif (k=="text") then
	    if (type(v)~="string") then return err("text value not a string"); end
	 elseif (k=="pos") then
	    if (type(v)~="number") then return err("pos value not a number"); end
	 elseif (k=="subs") then
	    for i,s in pairs(v) do
	       if type(i)~="number" then
		  return err("subs list has a non-numeric key")
	       end
	       local ok, msg = validate(s)
	       if not ok then
		  return err("in sub " .. tostring(i) .. ": " .. msg);
	       end
	    end -- loop through subs
	 else -- unrecognized key
	    return false, "unexpected key in body";
	 end -- switch on k
      end -- loop through body
   end -- all tests have passed
   return ast;
end

function generated_ast(node_name, ...)
   -- ... are the subs
   return common.create_match(node_name, 0, "*generated*", ...)
end

function make_transformer(fcn, target_name, recursive)
   local function transform (ast)
      local name, body = next(ast)
      if (target_name==nil) or (name==target_name) then
	 local new = common.create_match(name,
					 body.pos,
					 body.text,
					 table.unpack((recursive and map(transform, body.subs))
						      or body.subs))
	 return validate(fcn(new))
      else
	 return ast
      end
   end -- function transform
   return transform
end

-- function make_transformer(fcn, target_name, recursive)
--    local function transform (ast)
--       local name, orig_body = next(ast)
--       if (target_name==nil) or (name==target_name) then
-- 	 local new = validate(fcn(ast))
-- 	 local name, body = next(new)
-- 	 if recursive then
-- 	    local new_subs = 
-- 	       return common.create_match(name,
-- 					  body.pos,
-- 					  body.text,
-- 					  table.unpack(map(transform, body.subs)))
-- 	 else
-- 	    return new
-- 	 end
--       end
--    end -- function transform
--    return transform
-- end

----------------------------------------------------------------------------------------

cook_if_needed =
   make_transformer(function(ast)
		       local name, body = next(ast)
		       if (name=="raw") or (name=="cooked") then
			  return ast
		       else
			  return generated_ast("cooked", ast)
		       end
		    end,
		    nil,
		    false)


wraptest =
   make_transformer(function(ast)
		       return generated_ast("wrapped", ast)
		    end,
		    nil,
		    false)

wrapchoicetest = 
   make_transformer(function(ast)
		       return generated_ast("choice wrapped", ast)
		    end,
		    "choice",
		    false)



recwraptest =
   make_transformer(function(ast)
		       return generated_ast("rec wrapped", ast)
		    end,
		    nil,
		    true)


cooked_to_raw =
   make_transformer(function(ast)
		       local _, body = next(ast)
		       local sub = body.subs[1]
		       local name, subbody = next(sub)
		       assert((type(subbody)=="table") and next(subbody), "bad cooked node")
		       if name=="sequence" then
			  local s = generated_ast("sequence", sub, boundary_ast)
			  return generated_ast("raw", s)
		       else
			  -- other tests? choice?
			  return generated_ast("raw", sub) -- we lose the original text/pos here
		       end
		    end,
		    "cooked",
		    true)


--local compile = require "compile"
--local cinternals = compile.cinternals

-- Add to the Emacs command 'rosie':
   -- switch to rosie buffer if it exists
   -- memo of last rosie home dir used, if need to start rosie

-- Add a field to pattern record for "original_ast" where we can store the pre-transformation ast.


--local boundary_ast = cinternals.ENV[common.boundary_identifier].ast
--local boundary_ast = common.create_match("identifier", 0, common.boundary_identifier)

function _____cooked_to_raw(a)
   local name, pos, text, subs = common.decode_match(a)
   assert(name == "cooked")
   assert(#subs == 1)
   local exp = subs[1]
   if next(exp)=="sequence" then
      local name, pos, text, subs = common.decode_match(exp)
      assert(#subs == 2)			    -- two branches in a sequence
      local type1 = next(subs[1])
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
      local e = subs[1]
      local q = subs[2]
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

	 local qname, qpos, qtext, qsubs = common.decode_match(q)

	 e = macro_expand(e)

	 if qname=="plus" then
	    -- a => {e boundary}+
	 elseif qname=="star" then
	    -- a => {{e boundary}+}?                                 -- yep.
	 elseif qname=="question" then
	    -- a => {e boundary}?
	 elseif qname=="repetition" then
	    assert(type(qsubs[1])=="table")
	    assert(qsubs[1], "not getting min clause in cooked_to_raw")
	    local mname, mpos, mtext = common.decode_match(qsubs[1])
	    assert(mname=="low")
	    min = tonumber(mtext) or 0
	    assert(qsubs[2], "not getting max clause in cooked_to_raw")
	    local mname, mpos, mtext = common.decode_match(qsubs[2])
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





