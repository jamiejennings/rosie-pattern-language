---- -*- Mode: Lua; -*- 
----
---- syntax.lua   syntactic transformations (AST -> AST)
----
---- (c) 2016, Jamie A. Jennings
----

local common = require "common"			    -- AST functions
require "list"

syntax = {}

local boundary_ast = common.create_match("identifier", 0, common.boundary_identifier)
local looking_at_boundary_ast = common.create_match("lookat", 0, "@/generated/", boundary_ast)

local function err(name, msg)
   error('invalid ast "' .. name .. '" ' .. msg)
end

function syntax.validate(ast)
   if ast==nil then return nil; end
   if type(ast)~="table" then
      error("argument to validate is not an ast: " .. tostring(ast))
   end
   local name, body = next(ast)
   if type(name)~="string" then
      err(tostring(name), "is a non-string name");
   elseif next(ast, name) then
      err(name, "multiple names");
   elseif type(body)~="table" then
      err(name, "has a non-table body");
   else
      for k,v in pairs(body) do
	 if type(k)~="string" then err(name, "non-string key in body");
	 elseif (k=="text") then
	    if (type(v)~="string") then err(name, "text value not a string"); end
	 elseif (k=="pos") then
	    if (type(v)~="number") then err(name, "pos value not a number"); end
	 elseif (k=="subs") then
	    for i,s in pairs(v) do
	       if type(i)~="number" then
		  err(name, "subs list has a non-numeric key")
	       end
	       local ok, msg = syntax.validate(s)
	       if not ok then
		  err(name, "in sub " .. tostring(i) .. ": " .. msg);
	       end
	    end -- loop through subs
	 else -- unrecognized key
	    err(name, "unexpected key in ast body: " .. tostring(k));
	 end -- switch on k
      end -- loop through body
   end -- all tests have passed
   return ast;
end

function syntax.generated_ast(node_name, ...)
   -- ... are the subs
   return common.create_match(node_name, 0, "*generated*", ...)
end

function syntax.make_transformer(fcn, target_name, recursive)
   local function transform (ast, ...)
      local name, body = next(ast)
      local new = common.create_match(name,
				      body.pos,
				      body.text,
				      table.unpack((recursive and map(transform, body.subs))
						or body.subs))
      if (target_name==nil) or (name==target_name) then
	 return syntax.validate(fcn(new, ...))
      else
	 return syntax.validate(new)
      end
   end -- function transform
   return transform
end

function syntax.compose(f1, ...)
   -- return f1 o f2 o ... fn
   local fcns = {f1, ...}
   local composition = fcns[#fcns]
   for i = (#fcns - 1), 1, -1 do
      local previous = composition
      composition = function(...)
		       return fcns[i](previous(...))
		    end
   end
   return composition
end
	     

----------------------------------------------------------------------------------------

-- wraptest =
--    syntax.make_transformer(function(ast)
-- 		       return syntax.generated_ast("wrapped", ast)
-- 		    end,
-- 		    nil,
-- 		    false)
-- wrapchoicetest = 
--    syntax.make_transformer(function(ast)
-- 		       return syntax.generated_ast("choice wrapped", ast)
-- 		    end,
-- 		    "choice",
-- 		    true)
-- recwraptest =
--    syntax.make_transformer(function(ast)
-- 		       return syntax.generated_ast("rec wrapped", ast)
-- 		    end,
-- 		    nil,
-- 		    true)

syntax.capture =
   syntax.make_transformer(function(ast)
		       return syntax.generated_ast("capture", ast)
		    end,
		    nil,
		    false)

syntax.sequence =
   syntax.make_transformer(function(ast1, ast2)
			      return syntax.generated_ast("sequence", ast1, ast2)
			   end,
			   nil,
			   false)


syntax.cook_if_needed =
   syntax.make_transformer(function(ast)
		       local name, body = next(ast)
		       if (name=="raw") or (name=="cooked") then
			  return ast
		       else
			  return syntax.generated_ast("cooked", ast)
		       end
		    end,
		    nil,
		    false)

syntax.append_boundary =
   syntax.make_transformer(function(ast)
			      return syntax.generated_ast("sequence", ast, boundary_ast)
			   end,
			   "cooked",
			   false)


syntax.cooked_to_raw =
   syntax.make_transformer(function(ast)
		       local _, body = next(ast)
		       local sub = body.subs[1]
		       local name, subbody = next(sub)
		       assert((type(subbody)=="table") and next(subbody), "bad cooked node")
		       if name=="sequence" then
			  local first = subbody.subs[1]
			  local second = subbody.subs[2]
			  local s1 = syntax.generated_ast("sequence", first, boundary_ast)
			  local s2 = syntax.generated_ast("sequence", s1, second)
			  return syntax.generated_ast("raw", s2)
		       elseif name=="choice" then
			  local first = subbody.subs[1]
			  local second = subbody.subs[2]
			  local c1 = syntax.generated_ast("sequence", first, boundary_ast)
			  local c2 = syntax.generated_ast("sequence", second, boundary_ast)
			  local new_choice = syntax.generated_ast("choice", c1, c2)
			  return syntax.generated_ast("raw", new_choice)
		       else
			  return syntax.generated_ast("raw", table.unpack(body.subs))
		       end
		    end,
		    "cooked",
		    true)

syntax.top_level_transform = 
   syntax.compose(syntax.cooked_to_raw, syntax.append_boundary, syntax.cook_if_needed)




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


return syntax


