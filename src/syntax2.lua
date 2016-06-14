---- -*- Mode: Lua; -*- 
----
---- syntax.lua   syntactic transformations (AST -> AST)
----
---- (c) 2016, Jamie A. Jennings
----

local common = require "common"			    -- AST functions
require "list"

syntax2 = {}

local boundary_ast = common.create_match("ref", 0, common.boundary_identifier)
--local looking_at_boundary_ast = common.create_match("lookat", 0, "@/generated/", boundary_ast)
local looking_at_boundary_ast = common.create_match("predicate",
						    0,
						    "*generated*",
						    common.create_match("lookat", 0, "@"),
						    boundary_ast)



local function err(name, msg)
   error('invalid ast ' .. name .. ': ' .. msg)
end

function syntax2.validate(ast)
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
	       local ok, msg = syntax2.validate(s)
	       if not ok then
		  err(name, "in sub " .. tostring(i) .. ": " .. msg);
	       end
	    end -- loop through subs
	 elseif ((k=="capture") and (name=="binding")) then
	    if (type(v)~="boolean") then err(name, "value of the capture flag not a boolean"); end
	 else -- unrecognized key
	    err(name, "unexpected key in ast body: " .. tostring(k));
	 end -- switch on k
      end -- loop through body
   end -- all tests have passed
   return ast;
end

function syntax2.generate(node_name, ...)
   -- ... are the subs
   return common.create_match(node_name, 0, "*generated*", ...)
end

function syntax2.make_transformer(fcn, target_name, recursive)
   local function target_match(name)
         -- Either match every node
      if (target_name==nil) then return true;
	 -- Or a single node type
      elseif (type(target_name)=="string") then return (name==target_name);
	 -- Or a member of a list
      elseif (type(target_name)=="table") then return member(name, target_name)
      else error("illegal target type: " .. name .. "is not a string or list")
      end
   end -- function target_match
      
   local function transform (ast, ...)
      local name, body = next(ast)
      local rest = {...}
      local mapped_transform = function(ast) return transform(ast, table.unpack(rest)); end
      local new = common.create_match(name,
				      body.pos,
				      body.text,
				      table.unpack((recursive and map(mapped_transform, body.subs))
						or body.subs))
      if target_match(name) then
	 return syntax2.validate(fcn(new, ...))
      else
	 return syntax2.validate(new)
      end
   end -- function transform
   return transform
end

function syntax2.compose(f1, ...)
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

-- return a list of choices
function syntax2.flatten_choice(ast)
   local name, body = next(ast)
   if name=="choice" then
      return apply(append, map(syntax2.flatten_choice, body.subs))
   else
      return {ast}
   end
end

-- take a list of choices and build a binary choice ast
function syntax2.rebuild_choice(choices)
   if #choices==2 then
      return syntax2.generate("choice", choices[1], choices[2])
   else
      return syntax2.generate("choice", choices[1], syntax2.rebuild_choice(cdr(choices)))
   end
end
		    
syntax2.capture =
   syntax2.make_transformer(function(ast, id)
			      local name, body = next(ast)
			      return syntax2.generate("capture",
						     common.create_match("ref", 0, id),
						     ast)
			   end,
			   nil,
			   false)

syntax2.append_looking_at_boundary =
   syntax2.make_transformer(function(ast)
			      return syntax2.generate("sequence", ast, looking_at_boundary_ast)
			   end,
			   nil,
			   false)

syntax2.append_boundary =
   syntax2.make_transformer(function(ast)
			      return syntax2.generate("sequence", ast, boundary_ast)
			   end,
			   nil,
			   false)

syntax2.append_boundary_to_rhs =
   syntax2.make_transformer(function(ast)
			      local name, body = next(ast)
			      local lhs = body.subs[1]
			      local rhs = body.subs[2]
			      local b = syntax2.generate("binding", lhs, syntax2.append_boundary(rhs))
			      b.binding.text = body.text
			      b.binding.pos = body.pos
			      return b
			   end,
			   "binding",
			   false)

function transform_quantified_exp(ast)
   local new_exp = syntax2.id_to_ref(ast.quantified_exp.subs[1])
   local name, body = next(new_exp)
   local original_body = body
   if name=="raw" 
      or name=="charset" 
      or name=="named_charset"
      or name=="literal" 
      or name=="ref"
   then
      new_exp = syntax2.generate("raw_exp", syntax2.raw(new_exp))
   else
      while (name=="cooked") do			    -- in case of nested cooked groups
	 new_exp = body.subs[1]			    -- strip off "cooked"
	 name, body = next(new_exp)
      end
      new_exp = syntax2.cook(new_exp)		    -- treat it as raw, because we deal with cooked later
   end
   local new = syntax2.generate("new_quantified_exp", new_exp, ast.quantified_exp.subs[2])
   new.new_quantified_exp.text = original_body.text
   new.new_quantified_exp.pos = original_body.pos
   return new
end

syntax2.id_to_ref =
   syntax2.make_transformer(function(ast)
			      local name, body = next(ast)
			      return common.create_match("ref", body.pos, body.text)
			   end,
			   "identifier",
			   true)		    -- RECURSIVE

syntax2.raw =
   syntax2.make_transformer(function(ast)
			      local name, body = next(ast)
			      --print("entering syntax2.raw", name)
			      if name=="cooked" then
				 return syntax2.cook(body.subs[1])
			      elseif name=="raw" then
				 return syntax2.raw(body.subs[1]) -- strip off the "raw" group
			      elseif name=="identifier" then
				 return syntax2.id_to_ref(ast)
			      elseif name=="quantified_exp" then
				 return transform_quantified_exp(ast)
			      else
				 local new = syntax2.generate(name, table.unpack(map(syntax2.raw, body.subs)))
				 new[name].text = body.text
				 new[name].pos = body.pos
				 return new
			      end
			   end,
			   nil,			    -- match all nodes
			   false)		    -- NOT recursive

syntax2.cook =
   syntax2.make_transformer(function(ast)
			      local name, body = next(ast)
			      --print("entering syntax2.cook", name)
			      if name=="raw" then
				 local raw_exp = syntax2.raw(body.subs[1])
				 return raw_exp
			      elseif name=="cooked" then
				 return syntax2.cook(body.subs[1]) -- strip off "cooked" node
			      elseif name=="identifier" then
				 --return syntax2.append_looking_at_boundary(syntax2.id_to_ref(ast))
				 return syntax2.id_to_ref(ast)
			      elseif name=="sequence" then
				 local first = body.subs[1]
				 local second = body.subs[2]
				 -- If the first sequent is a predicate, then no boundary is added
				 if next(first)=="predicate" then
				    return syntax2.generate("sequence", syntax2.cook(body.subs[1]), syntax2.cook(body.subs[2]))
				 end
				 local s1 = syntax2.generate("sequence", syntax2.cook(first), boundary_ast)
				 local s2 = syntax2.generate("sequence", s1, syntax2.cook(second))
				 return s2
			      elseif name=="choice" then
				 local first = body.subs[1]
				 local second = body.subs[2]
				 -- local c1 = syntax2.generate("sequence", syntax2.cook(first), looking_at_boundary_ast)
				 -- local c2 = syntax2.generate("sequence", syntax2.cook(second), looking_at_boundary_ast)
				 local c1 = syntax2.cook(first)
				 local c2 = syntax2.cook(second)
				 local new_choice = syntax2.generate("choice", c1, c2)
				 return new_choice
			      elseif name=="quantified_exp" then
				 -- do some involved stuff here
				 -- which we will skip for now
				 return transform_quantified_exp(ast)
			       else
				  local new = syntax2.generate(name, table.unpack(map(syntax2.cook, body.subs)))
				  new[name].text = body.text
				  new[name].pos = body.pos
				  return new
			       end
			    end,
			   nil,			    -- match all nodes
			   false)		    -- NOT recursive

syntax2.cook_rhs =
   syntax2.make_transformer(function(ast)
			      local name, body = next(ast)
			      local lhs = body.subs[1]
			      local rhs = body.subs[2]
			      local new_rhs = syntax2.cook(rhs)
			      local b = syntax2.generate("binding", lhs, new_rhs)
			      b.binding.text = body.text
			      b.binding.pos = body.pos
			      return b
			   end,
			   "binding",
			   false)

syntax2.cooked_to_raw =
   syntax2.make_transformer(function(ast)
			      local name, body = next(ast)
			      if name=="raw" then
				 -- re-wrap the top level with "raw_exp" so that we know at top level
				 -- not to append a boundary
				 return syntax2.generate("raw_exp", syntax2.raw(ast))
			      else
				 return syntax2.cook(ast)
			      end
			   end,
			   nil,
			   false)

function syntax2.expand_rhs(ast, original_rhs_name)
   local name, body = next(ast)
   if original_rhs_name=="raw" then
      -- wrap with "raw_exp" so that we know at top level not to append a boundary
      return syntax2.generate("raw_exp", syntax2.raw(ast))
   elseif original_rhs_name=="cooked" then
	 return syntax2.cook(ast)
   elseif original_rhs_name=="identifier" then
      -- neither cooked nor raw, the rawness of a ref depends on
      -- following the reference
      return syntax2.id_to_ref(ast)
   elseif name=="ref" then
      return ast(ast)
   elseif name=="capture" then
      return syntax.generate("capture", body.subs[1], syntax2.expand_rhs(body.subs[2]))
   elseif syntax2.expression_p(ast) then
      local new = ast
      if ((name=="raw") or (name=="literal") or (name=="charset") or
          (name=="named_charset") or (name=="predicate")) then
      	 new = syntax2.raw(new)
      else
      	 new = syntax2.cook(new)
      end
      return syntax2.generate("raw_exp", new)
   else
      error("Error in transform: unrecognized parse result: " .. name)
   end
end

syntax2.to_binding = 
   syntax2.make_transformer(function(ast)
			      local name, body = next(ast)
			      local lhs = body.subs[1]
			      local rhs = body.subs[2]
			      local original_rhs_name = next(rhs)
			      if (name=="assignment_") then
				 local name, pos, text, subs = common.decode_match(lhs)
				 assert(name=="identifier")
				 rhs = syntax2.capture(syntax2.expand_rhs(rhs, original_rhs_name), text)
			      else
				 rhs = syntax2.expand_rhs(rhs, original_rhs_name)
			      end
			      local b = syntax2.generate("binding", lhs, rhs)
			      b.binding.capture = (name=="assignment_")
			      b.binding.text = body.text
			      b.binding.pos = body.pos
			      return b
			   end,
			    {"assignment_", "alias_"},
			    false)

-- At top level:
--   If the exp to match is an identifier, then look it up in the env.
--     If the pattern is marked as "raw" then match its peg.
--     If the pattern is marked as "cooked", then match its peg followed by a boundary.
--   Else we don't have an identifier, so do this:
--     Transform the exp as we would the rhs of an assignment (which includes capturing a value).
--     Compile the exp to a pattern.
--     Proceed as above based on whether the pattern is marked "raw" or not.

-- syntax2.top_level_transform =
--    syntax2.compose(syntax2.cooked_to_raw, syntax2.capture)

function syntax2.expression_p(ast)
   local name, body = next(ast)
   return ((name=="identifier") or
	   (name=="raw") or
	   (name=="raw_exp") or
	   (name=="cooked") or
	   (name=="literal") or
	   (name=="quantified_exp") or
	   (name=="named_charset") or
	   (name=="charset") or
	   (name=="choice") or
	   (name=="sequence") or
	   (name=="predicate"))
end

function syntax2.top_level_transform(ast)
   local name, body = next(ast)
   if (name=="assignment_") or (name=="alias_") then
      return syntax2.to_binding(ast)
   elseif (name=="grammar_") then
      local new_bindings = map(syntax2.to_binding, ast.grammar_.subs)
      local new = syntax2.generate("new_grammar", table.unpack(new_bindings))
      new.new_grammar.text = ast.grammar_.text
      new.new_grammar.pos = ast.grammar_.pos
      return new
   elseif (name=="syntax_error") then
      return ast				    -- errors will be culled out later
   else
      return syntax2.expand_rhs(ast, (next(ast)))
   end
end

-- function syntax2.contains_capture(ast)
--    local name, body = next(ast)
--    if name=="capture" then return true; end
--    return reduce(or_function, false, map(syntax2.contains_capture, body.subs))
-- end

---------------------------------------------------------------------------------------------------
-- Testing
---------------------------------------------------------------------------------------------------
-- syntax2.assignment_to_alias =
--    syntax2.make_transformer(function(ast)
-- 			      local name, body = next(ast)
-- 			      local lhs = body.subs[1]
-- 			      local rhs = body.subs[2]
-- 			      local b = syntax2.generate("alias_", lhs, rhs)
-- 			      b.alias_.text = body.text
-- 			      b.alias_.pos = body.pos
-- 			      return b
-- 			   end,
-- 			   "assignment_",
-- 			   false)

return syntax2


