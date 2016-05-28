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

function syntax.generate(node_name, ...)
   -- ... are the subs
   return common.create_match(node_name, 0, "*generated*", ...)
end

function syntax.make_transformer(fcn, target_name, recursive)
   local function transform (ast, ...)
      local name, body = next(ast)
      local rest = {...}
      local mapped_transform = function(ast) return transform(ast, table.unpack(rest)); end
      local new = common.create_match(name,
				      body.pos,
				      body.text,
				      table.unpack((recursive and map(mapped_transform, body.subs))
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

syntax.capture =
   syntax.make_transformer(function(ast)
			      -- local name, body = next(ast)
			      -- if (name=="cooked") then
			      -- 	 return syntax.generate("cooked",
			      -- 				     syntax.generate("capture", ast))
			      -- else
			      return syntax.generate("capture", ast)
			   -- end
			   end,
			   nil,
			   false)

syntax.sequence =
   syntax.make_transformer(function(ast1, ast2)
			      return syntax.generate("sequence", ast1, ast2)
			   end,
			   nil,
			   false)


syntax.cook_if_needed =
   syntax.make_transformer(function(ast)
		       local name, body = next(ast)
		       if (name=="raw") or (name=="cooked") then
			  return ast
		       -- elseif (name=="capture") then
		       -- 	  local name, body = next(body.subs[1])
		       -- 	  if (name=="raw") or (name=="cooked") then
		       -- 	     return ast
		       -- 	  else
		       -- 	     -- put the capture INSIDE the cooked group
		       -- 	     return syntax.generate("cooked", ast)
		       -- 	  end
		       else
			  return syntax.generate("cooked", ast)
		       end
		    end,
		    nil,
		    false)

syntax.cook_rhs_if_needed =
   syntax.make_transformer(function(ast)
			      local name, body = next(ast)
			      local lhs = body.subs[1]
			      local new_rhs = syntax.cook_if_needed(body.subs[2])
			      local b = syntax.generate("assignment_", lhs, new_rhs)
			      b.assignment_.text = body.text
			      b.assignment_.pos = body.pos
			      return b
			   end,
			   "assignment_",
			   false)

syntax.append_boundary =
   syntax.make_transformer(function(ast)
			      return syntax.generate("sequence", ast, boundary_ast)
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
			  -- Do we need to check to see if 'first' is a predicate (e.g. look ahead
			  -- or negation)?  
			  local first = subbody.subs[1]
			  local second = subbody.subs[2]
			  local s1 = syntax.generate("sequence", first, boundary_ast)
			  local s2 = syntax.generate("sequence", s1, second)
			  return syntax.generate("raw", s2)
		       elseif name=="choice" then
			  local first = subbody.subs[1]
			  local second = subbody.subs[2]
			  local c1 = syntax.generate("sequence", first, boundary_ast)
			  local c2 = syntax.generate("sequence", second, boundary_ast)
			  local new_choice = syntax.generate("choice", c1, c2)
			  return syntax.generate("raw", new_choice)
		       elseif name=="capture" then
			  return syntax.generate("sequence",
						 sub, -- the capture
						 boundary_ast)
		       else
			  return body.subs[1]	    -- strip off the "cooked" node
		       end
		    end,
		    "cooked",
		    true)

syntax.cooked_to_raw_capture =
   syntax.make_transformer(function(ast)
		       local _, body = next(ast)
		       local sub = body.subs[1]
		       local name, subbody = next(sub)
		       assert((type(subbody)=="table") and next(subbody), "bad cooked node")
		       if name=="sequence" then
			  -- Do we need to check to see if 'first' is a predicate (e.g. look ahead
			  -- or negation)?  
			  local first = syntax.capture(subbody.subs[1])
			  local second = syntax.capture(subbody.subs[2])
			  local s1 = syntax.generate("sequence", first, boundary_ast)
			  local s2 = syntax.generate("sequence", s1, second)
			  return syntax.generate("raw", s2)
		       elseif name=="choice" then
			  local first = syntax.capture(subbody.subs[1])
			  local second = syntax.capture(subbody.subs[2])
			  local c1 = syntax.generate("sequence", first, boundary_ast)
			  local c2 = syntax.generate("sequence", second, boundary_ast)
			  local new_choice = syntax.generate("choice", c1, c2)
			  return syntax.generate("raw", new_choice)
		       elseif name=="quantified_exp" then
			  -- do some involved stuff here
			  -- which we will skip for now
			  local s1 = syntax.generate("sequence", syntax.capture(sub), boundary_ast)
			  return syntax.generate("raw", s1)
		       -- elseif name=="capture" then
		       -- 	  return syntax.generate("sequence",
		       -- 				 sub, -- the capture
						 -- boundary_ast)
		       else
			  return syntax.capture(body.subs[1])
		       end
		    end,
		    "cooked",
		    true)

syntax.assignment_to_binding =
   syntax.make_transformer(function(ast)
			      local name, body = next(ast)
			      local lhs = body.subs[1]
			      local rhs = body.subs[2]
			      local new_rhs = syntax.cook_if_needed(rhs)
			      assert((next(new_rhs)=="cooked") or (next(new_rhs)=="raw"))
			      new_rhs = syntax.cooked_to_raw_capture(new_rhs)
			      local b = syntax.generate("binding", lhs, new_rhs)
			      b.binding.text = body.text
			      b.binding.pos = body.pos
			      return b
			   end,
			   "assignment_",
			   false)

syntax.top_level_transform = 
   syntax.compose(syntax.cooked_to_raw, syntax.append_boundary, syntax.cook_if_needed)


-- syntax.assignment_transform = 
--    syntax.compose(syntax.assignment_to_binding, syntax.cook_rhs_if_needed)


return syntax


