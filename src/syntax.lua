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
			      local name, body = next(ast)
			      if (name=="cooked") or (name=="raw") then
				 -- put the capture inside the group instead of outside
				 local inside = body.subs[1]
			      	 return syntax.generate(name, syntax.generate("capture", inside))
			      else
				 return syntax.generate("capture", ast)
			      end
			   end,
			   nil,
			   false)

syntax.capture_rhs =
   syntax.make_transformer(function(ast)
			      local name, body = next(ast)
			      local lhs = body.subs[1]
			      local new_rhs = syntax.capture(body.subs[2])
			      local b = syntax.generate("assignment_", lhs, new_rhs)
			      b.assignment_.text = body.text
			      b.assignment_.pos = body.pos
			      return b
			   end,
			   "assignment_",
			   false)

syntax.sequence =
   syntax.make_transformer(function(ast1, ast2)
			      return syntax.generate("sequence", ast1, ast2)
			   end,
			   nil,
			   false)


syntax.append_boundary =
   syntax.make_transformer(function(ast)
			      return syntax.generate("sequence", ast, boundary_ast)
			   end,
			   nil,
			   false)

syntax.append_boundary_to_rhs =
   syntax.make_transformer(function(ast)
			      local name, body = next(ast)
			      local lhs = body.subs[1]
			      local rhs = body.subs[2]
			      local b = syntax.generate("binding", lhs, syntax.append_boundary(rhs))
			      b.binding.text = body.text
			      b.binding.pos = body.pos
			      return b
			   end,
			   "binding",
			   false)

syntax.raw =
   syntax.make_transformer(function(ast)
			      local name, body = next(ast)
			      if name=="cooked" then
				 return syntax.cook(ast)
			      elseif name=="raw" then
				 return body.subs[1] -- strip off the "raw" group
			      else
				 return ast
			      end
			   end,
			   nil,
			   true)

syntax.cook =
   syntax.make_transformer(function(ast)
			      local name, body = next(ast)
			      if name=="sequence" then
				 -- Do we need to check to see if 'first' is a predicate (e.g. look ahead
				 -- or negation)?  
				 local first = body.subs[1]
				 local second = body.subs[2]
				 local s1 = syntax.generate("sequence", first, boundary_ast)
				 local s2 = syntax.generate("sequence", s1, second)
				 return s2
			      elseif name=="choice" then
				 local first = body.subs[1]
				 local second = body.subs[2]
				 local c1 = syntax.generate("sequence", first, boundary_ast)
				 local c2 = syntax.generate("sequence", second, boundary_ast)
				 local new_choice = syntax.generate("choice", c1, c2)
				 return new_choice
			      elseif name=="quantified_exp" then
				 -- do some involved stuff here
				 -- which we will skip for now
				 local temp_name = "cooked_quantified_exp"
				 local s1 = syntax.generate(temp_name, table.unpack(body.subs))
				 s1[temp_name].text = body.text
				 s1[temp_name].pos = body.pos
				 return s1
			      elseif name=="cooked" then
				 return body.subs[1] -- strip out the cooked
			      elseif name=="raw" then
				 local raw_exp = syntax.raw(body.subs[1])
				 local kind = next(raw_exp)
				 raw_exp[kind].text = body.text
				 raw_exp[kind].pos = body.pos
				 return raw_exp
			      else
				 return ast
			      end
			   end,
			   nil,			    -- match any ast node
			   true)		    -- recursive

syntax.cook_rhs =
   syntax.make_transformer(function(ast)
			      local name, body = next(ast)
			      local lhs = body.subs[1]
			      local rhs = body.subs[2]
			      local new_rhs = syntax.cook(rhs)
			      local b = syntax.generate("binding", lhs, new_rhs)
			      b.binding.text = body.text
			      b.binding.pos = body.pos
			      return b
			   end,
			   "binding",
			   false)

syntax.to_binding = 
   syntax.make_transformer(function(ast)
			      local name, body = next(ast)
			      assert((name=="assignment_") or (name=="alias_"))
			      local lhs = body.subs[1]
			      local rhs = body.subs[2]
			      local rhs_name = next(rhs)
			      if (name=="assignment_") then rhs = syntax.capture(rhs); end
			      local b = syntax.generate("binding", lhs, rhs)
			      if rhs_name=="raw" then
				 b = syntax.raw(b)
			      else
				 b = syntax.append_boundary_to_rhs(syntax.cook(b))
			      end
			      b.binding.text = body.text
			      b.binding.pos = body.pos
			      return b
			   end,
			   {"assignment_", "alias_"},
			   false)

---------------------------------------------------------------------------------------------------
-- Testing
---------------------------------------------------------------------------------------------------
syntax.assignment_to_alias =
   syntax.make_transformer(function(ast)
			      local name, body = next(ast)
			      local lhs = body.subs[1]
			      local rhs = body.subs[2]
			      local b = syntax.generate("alias_", lhs, rhs)
			      b.alias_.text = body.text
			      b.alias_.pos = body.pos
			      return b
			   end,
			   "assignment_",
			   false)

function syntax.test()
   print("Re-loading syntax package...") 
   package.loaded.syntax = false; syntax = require "syntax"
   a = compile.parser("int = [:digit:]+")[1]
   b = compile.parser("int = ([:digit:]+)")[1]
   c = compile.parser("int = {[:digit:]+}")[1]
   d = compile.parser("int = {([:digit:] [:digit:])}")[1]
   e = compile.parser("int = ([:digit:] [:digit:])")[1]
   print("Testing assignment_to_binding on 'a'...")
   table.print(syntax.to_binding(a))
   print("Testing alias_to_binding on alias version of 'a'...")
   aa = syntax.assignment_to_alias(a)
   table.print(syntax.to_binding(aa))
end

return syntax


