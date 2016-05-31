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
			      return syntax.generate("capture", ast)
			   end,
			   nil,
			   false)

---------------------------------------------------------------------------------------------------
if false then
   syntax.capture_assignment_rhs =
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
end -- if false
---------------------------------------------------------------------------------------------------

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
			      --print("entering syntax.raw", name)
			      if name=="cooked" then
				 return syntax.cook(body.subs[1])
			      elseif name=="raw" then
				 return syntax.raw(body.subs[1]) -- strip off the "raw" group
			      else
				 local new = syntax.generate(name, table.unpack(map(syntax.raw, body.subs)))
				 new[name].text = body.text
				 new[name].pos = body.pos
				 return new
			      end
			   end,
			   nil,			    -- match all nodes
			   false)		    -- NOT recursive

function predicate_p(ast)
   local name, body = next(ast)
   return ((name=="lookat") or
	(name=="negation"))
end

syntax.cook =
   syntax.make_transformer(function(ast)
			      local name, body = next(ast)
			      --print("entering syntax.cook", name)
			      if name=="raw" then
				 local raw_exp = syntax.raw(body.subs[1])
				 local kind = next(raw_exp)
				 raw_exp[kind].text = body.text
				 raw_exp[kind].pos = body.pos
				 return raw_exp
			      elseif name=="cooked" then
				 return syntax.cook(body.subs[1]) -- strip off "cooked" node
			      elseif name=="sequence" then
				 local first = body.subs[1]
				 local second = body.subs[2]
				 -- If the first sequent is a predicate, then no boundary is added
				 if predicate_p(first) then return ast; end
				 local s1 = syntax.generate("sequence", syntax.cook(first), boundary_ast)
				 local s2 = syntax.generate("sequence", s1, syntax.cook(second))
				 return s2
			      elseif name=="choice" then
				 local first = body.subs[1]
				 local second = body.subs[2]
				 local c1 = syntax.generate("sequence", syntax.cook(first), boundary_ast)
				 local c2 = syntax.generate("sequence", syntax.cook(second), boundary_ast)
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
			      else
				 local new = syntax.generate(name, table.unpack(map(syntax.cook, body.subs)))
				 new[name].text = body.text
				 new[name].pos = body.pos
				 return new
			      end
			   end,
			   nil,			    -- match all nodes
			   false)		    -- NOT recursive

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

syntax.cooked_to_raw =
   syntax.make_transformer(function(ast)
			      local name, body = next(ast)
			      if name=="raw" then
				 ast = syntax.raw(ast)
				 -- re-wrap the top level with "raw" so that we know at top level
				 -- not to append a boundary
				 return syntax.generate("raw", ast)
			      else
				 return syntax.cook(ast)
			      end
			   end,
			   nil,
			   false)
syntax.to_binding = 
   syntax.make_transformer(function(ast)
			      local name, body = next(ast)
			      assert((name=="assignment_") or (name=="alias_"))
			      local lhs = body.subs[1]
			      local rhs = body.subs[2]
			      local rhs_name = next(rhs)
			      if (name=="assignment_") then rhs = syntax.capture(rhs); end
			      local b = syntax.generate("binding", lhs, syntax.cooked_to_raw(rhs))
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
--     Proceed as above based on whether the pattern is marked "raw" or "cooked".

syntax.top_level_transform =
   syntax.compose(syntax.cooked_to_raw, syntax.capture)

   -- syntax.make_transformer(function(ast)
   -- 			      local name, body = next(ast)
   -- 			      local b
   -- 			      if name=="binding" then
   -- 				 b = ast
   -- 			      else
   -- 				 local a = syntax.generate("assignment_",
   -- 							   common.create_match("identifier",
   -- 									       0,
   -- 									       "*"),
   -- 							   ast)
   -- 				 a.assignment_.text = body.text
   -- 				 a.assignment_.pos = body.pos
   -- 				 b = syntax.to_binding(a)
   -- 			      end
   -- 			      local name, body = next(b)
   -- 			      local rhs_name, rhs_body = next(body.subs[2])
   -- 			      if rhs_name=="raw" then
   -- 				 body.subs[2] = rhs_body.subs[1] -- strip off "raw"
   -- 			      else
   -- 				 body.subs[2] = syntax.append_boundary(body.subs[2])
   -- 			      end
   -- 			      return b
   -- 			   end,
   -- 			   nil,
   -- 			   false)



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

parse = require "parse" 
function syntax.test()
   print("Re-loading syntax package...") 
   package.loaded.syntax = false; syntax = require "syntax"
   print("Assigning a bunch of globals for testing...")
   -- globals to make it easier to continue testing and debugging manually
   a = compile.parser("int = [:digit:]+")[1]
   b = compile.parser("int = ([:digit:]+)")[1]
   c = compile.parser("int = {[:digit:]+}")[1]
   d = compile.parser("int = {([:digit:] [:digit:])}")[1]
   e = compile.parser("int = ([:digit:] [:digit:])")[1]
   aa = syntax.assignment_to_alias(a)
   bb = syntax.assignment_to_alias(b)
   cc = syntax.assignment_to_alias(c)
   dd = syntax.assignment_to_alias(d)
   ee = syntax.assignment_to_alias(e)
   local function run(label, lst)
      print(label)
      for _,v in ipairs(lst) do
	 print()
	 local b = syntax.to_binding(v)
	 local rhs = b.binding.subs[2]
	 io.write(parse.reveal_ast(v), "\n===========>  ", parse.reveal_ast(b), "\n")
	 local v_name, v_body = next(v)
	 local original_rhs = v_body.subs[2]
	 local notraw = (next(original_rhs)~="raw")
	 local top_level
	 if next(rhs)=="capture" then 		    -- resulted from assignment
	    top_level = parse.reveal_ast(rhs)
	 else					    -- was an alias or other
	    top_level = parse.reveal_ast(syntax.top_level_transform(rhs))
	 end
	 if notraw then
	    top_level = top_level .. " *BOUNDARY* "
	 end
	 io.write("top level =>  ", top_level, "\n")
      end
      print()
   end
   run("Assignment tests:", {a, b, c, d, e})
   run("Alias tests:", {aa, bb, cc, dd, ee})

   local f = io.open(common.compute_full_path("rpl/common.rpl"))
   local s = f:read("a")
   f:close()
   p = parse.parse(s)
   cmi = p[#p]
   -- run an entire file
   run("FILE common.rpl:", p)
end

return syntax


