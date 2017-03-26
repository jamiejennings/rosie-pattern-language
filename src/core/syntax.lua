---- -*- Mode: Lua; -*- 
----
---- syntax.lua   syntactic transformations (AST -> AST)
----
---- (c) 2016, Jamie A. Jennings
----

local common = require "common"			    -- AST functions
local list = require "list"

local function err(...)
   error(table.concat({...}, " "))
end

local syntax = {}

-- When a syntax transformation uses the boundary, it uses a reference to the boundary
-- identifier so that it gets the current value of the boundary pattern.
local boundary_ast = common.create_match("ref", 0, common.boundary_identifier)
local looking_at_boundary_ast = common.create_match("predicate",
						    0,
						    "*generated*",
						    common.create_match("lookat", 0, "@"),
						    boundary_ast)

local dot_ast = common.create_match("ref", 0, common.any_char_identifier)
local eol_ast = common.create_match("ref", 0, common.end_of_input_identifier)

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
	 elseif ((k=="capture") and (name=="binding")) then
	    if (type(v)~="boolean") then err(name, "value of the capture flag not a boolean"); end
	 elseif (k=="replaces") then
	    if (type(v)~="table") then err(name, "value of the 'replaces' field not an AST"); end
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
      elseif (type(target_name)=="table") then return list.member(name, list.from(target_name))
      else error("illegal target type: " .. name .. "is not a string or list")
      end
   end -- function target_match
      
   local function transform (ast, ...)
      local name, body = next(ast)
      local rest = {...}
      local mapped_transform = function(ast) return transform(ast, table.unpack(rest)); end
      local new
      if body.subs then
	 new = common.create_match(name,
				   body.pos,
				   body.text,
				   table.unpack((recursive and list.map(mapped_transform, list.from(body.subs)))
					     or body.subs))
      else
	 new = common.create_match(name,
				   body.pos,
				   body.text)
      end
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

-- return a list of choices
function syntax.flatten_choice(ast)
   local name, body = next(ast)
   if name=="choice" then
      return list.apply(list.append, list.map(syntax.flatten_choice, list.from(body.subs)))
   else
      return {ast}
   end
end

-- take a list of choices and build a binary choice ast
function syntax.rebuild_choice(choices)
   if #choices==2 then
      return syntax.generate("choice", choices[1], choices[2])
   else
      return syntax.generate("choice", choices[1], syntax.rebuild_choice(list.cdr(list.from(choices))))
   end
end
		    
syntax.capture =
   syntax.make_transformer(function(ast, id)
			      local name, body = next(ast)
			      return syntax.generate("capture",
						     common.create_match("ref", 0, id),
						     ast)
			   end,
			   nil,
			   false)

syntax.append_looking_at_boundary =
   syntax.make_transformer(function(ast)
			      return syntax.generate("sequence", ast, looking_at_boundary_ast)
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

local function transform_quantified_exp(ast)
   local new_exp = syntax.id_to_ref(ast.quantified_exp.subs[1])
   local name, body = next(new_exp)
   local original_body = body
   if name=="raw" 
      or name=="charset" 
      or name=="named_charset" or name=="named_charset0"
      or name=="literal" or name=="literal0" 
      or name=="ref"
   then
      new_exp = syntax.generate("raw_exp", syntax.raw(new_exp))
   else
      while (name=="cooked") do			    -- in case of nested cooked groups
	 new_exp = body.subs[1]			    -- strip off "cooked"
	 name, body = next(new_exp)
      end
      new_exp = syntax.cook(new_exp)		    -- treat it as raw, because we deal with cooked later
   end
   local new = syntax.generate("new_quantified_exp", new_exp, ast.quantified_exp.subs[2])
   new.new_quantified_exp.text = original_body.text
   new.new_quantified_exp.pos = original_body.pos
   return new
end

syntax.id_to_ref =
   syntax.make_transformer(function(ast)
			      local name, body = next(ast)
			      return common.create_match("ref", body.pos, body.text)
			   end,
			   "identifier",
			   true)		    -- RECURSIVE

syntax.raw =
   syntax.make_transformer(function(ast)
			      local name, body = next(ast)
			      --print("entering syntax.raw", name)
			      if name=="cooked" then
				 return syntax.cook(body.subs[1])
			      elseif name=="raw" then
				 return syntax.raw(body.subs[1]) -- strip off the "raw" group
			      elseif name=="identifier" then
				 return syntax.id_to_ref(ast)
			      elseif name=="quantified_exp" then
				 return transform_quantified_exp(ast)
			      else
				 local new
				 if body.subs then
				    new = syntax.generate(name, table.unpack(list.map(syntax.raw, list.from(body.subs))))
				 else
				    new = syntax.generate(name)
				 end
				 new[name].text = body.text
				 new[name].pos = body.pos
				 return new
			      end
			   end,
			   nil,			    -- match all nodes
			   false)		    -- NOT recursive

syntax.cook =
   syntax.make_transformer(function(ast)
			      local name, body = next(ast)
			      --print("entering syntax.cook", name)
			      if name=="raw" then
				 local raw_exp = syntax.raw(body.subs[1])
				 return raw_exp
			      elseif name=="cooked" then
				 return syntax.cook(body.subs[1]) -- strip off "cooked" node
			      elseif name=="identifier" then
				 --return syntax.append_looking_at_boundary(syntax.id_to_ref(ast))
				 return syntax.id_to_ref(ast)
			      elseif name=="sequence" then
				 local first = body.subs[1]
				 local second = body.subs[2]
				 -- If the first sequent is a predicate, then no boundary is added
				 if next(first)=="predicate" then
				    return syntax.generate("sequence", syntax.cook(body.subs[1]), syntax.cook(body.subs[2]))
				 end
				 local s1 = syntax.generate("sequence", syntax.cook(first), boundary_ast)
				 local s2 = syntax.generate("sequence", s1, syntax.cook(second))
				 return s2
			      elseif name=="choice" then
				 local first = body.subs[1]
				 local second = body.subs[2]
				 -- local c1 = syntax.generate("sequence", syntax.cook(first), looking_at_boundary_ast)
				 -- local c2 = syntax.generate("sequence", syntax.cook(second), looking_at_boundary_ast)
				 local c1 = syntax.cook(first)
				 local c2 = syntax.cook(second)
				 local new_choice = syntax.generate("choice", c1, c2)
				 return new_choice
			      elseif name=="quantified_exp" then
				 -- do some involved stuff here
				 -- which we will skip for now
				 return transform_quantified_exp(ast)
			       else
				 local new
				 if body.subs then
				    new = syntax.generate(name, table.unpack(list.map(syntax.cook, list.from(body.subs))))
				 else
				    new = syntax.generate(name)
				 end
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
				 -- re-wrap the top level with "raw_exp" so that we know at top level
				 -- not to append a boundary
				 return syntax.generate("raw_exp", syntax.raw(ast))
			      else
				 return syntax.cook(ast)
			      end
			   end,
			   nil,
			   false)

syntax.expand_charset_exp =
   syntax.make_transformer(function(ast)
			      local name, pos, text, subs = common.decode_match(ast)
			      assert(subs and subs[1])
			      local complement = (next(subs[1])=="complement")
			      if complement then subs=list.cdr(list.from(subs)); end
			      assert(subs and subs[1])
			      local exp 
			      if subs[2] then
				 exp = syntax.rebuild_choice(subs)
			      else
				 exp = subs[1]
			      end
			      if complement then
			      	 exp = syntax.generate("sequence",
						       syntax.generate("predicate",
								       common.create_match("negation", 0, "!"),
								       exp),
						       dot_ast)
			      end
			      return syntax.generate("raw", exp)    -- not raw_exp!
			   end,
			   "charset_exp",	    -- applies only to these nodes
			   true)		    -- recursive
   
function syntax.expand_rhs(ast, original_rhs_name)
   ast = syntax.expand_charset_exp(ast)
   local name, body = next(ast)
   if original_rhs_name=="raw" then
      local new = syntax.generate("raw_exp", syntax.raw(ast))
      new.raw_exp.replaces = ast
      return new
   elseif original_rhs_name=="cooked" then
      local new = syntax.cook(ast)
      local name = next(new)
      new[name].replaces = ast
      return new
   elseif original_rhs_name=="identifier" then
      -- neither cooked nor raw, the rawness of a ref depends on
      -- following the reference
      return syntax.id_to_ref(ast)
--   elseif name=="ref" then
--      return ast(ast)				    -- ???
   elseif name=="capture" then
      return syntax.generate("capture", body.subs[1], syntax.expand_rhs(body.subs[2]))
   elseif name=="syntax_error" then
      return ast
   elseif syntax.expression_p(ast) then
      local new = ast
      if ((name=="raw") or (name=="literal") or (name=="literal0") or
          (name=="charset") or (name=="charset_exp") or
          (name=="named_charset") or (name=="named_charset0") or
          (name=="range") or (name=="charlist") or 
          (name=="predicate")) then
      	 new = syntax.raw(new)
      else
      	 new = syntax.cook(new)
      end
      new = syntax.generate("raw_exp", new)
      new.raw_exp.replaces = ast
      return new
   else
      error("Error in transform: unrecognized parse result: " .. name)
   end
end

syntax.to_binding = 
   syntax.make_transformer(function(ast)
			      local name, body = next(ast)
			      local lhs = body.subs[1]
			      local rhs = body.subs[2]
			      local original_rhs_name = next(rhs)
			      if (name=="assignment_") then
				 local name, pos, text, subs = common.decode_match(lhs)
				 assert(name=="identifier")
				 rhs = syntax.capture(syntax.expand_rhs(rhs, original_rhs_name), text)
			      else
				 rhs = syntax.expand_rhs(rhs, original_rhs_name)
			      end
			      local b = syntax.generate("binding", lhs, rhs)
			      b.binding.capture = (name=="assignment_")
			      --b.binding.replaces = ast -- N.B. in rpl 0.0, 1.0 the binding ast is discarded
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

function syntax.expression_p(ast)
   local name, body = next(ast)
   return ((name=="identifier") or
	   (name=="raw") or
	   (name=="raw_exp") or
	   (name=="cooked") or
	   (name=="literal") or (name=="literal0") or
	   (name=="quantified_exp") or
	   (name=="named_charset") or (name=="named_charset0") or
	   (name=="range") or
	   (name=="charlist") or
	   (name=="charset_exp") or
--	   (name=="charset") or			    -- only used by core
	   (name=="choice") or
	   (name=="sequence") or
	   (name=="predicate"))
end

function syntax.top_level_transform0(ast)
   local name, body = next(ast)
   if (name=="assignment_") or (name=="alias_") then
      return syntax.to_binding(ast)
   elseif (name=="grammar_") then
      local new_bindings = list.map(syntax.to_binding, list.from(ast.grammar_.subs))
      local new = syntax.generate("new_grammar", table.unpack(new_bindings))
      new.new_grammar.text = ast.grammar_.text
      new.new_grammar.pos = ast.grammar_.pos
      new.new_grammar.replaces = ast
      return new
   elseif (name=="syntax_error") then
      return ast				    -- errors will be culled out later
   else
      return syntax.expand_rhs(ast, (next(ast)))
   end
end

function syntax.top_level_transform1(ast)
   local name, body = next(ast)
   if name=="statement" then
      local name = common.decode_match(body.subs[1])
      assert(name=="alias_" or name=="assignment_" or name=="grammar_" or name=="local_")
      -- strip off the 'statement' wrapper
      return syntax.top_level_transform1(body.subs[1])
   elseif (name=="assignment_") or (name=="alias_") then
      return syntax.to_binding(ast)
   elseif (name=="grammar_") then
      local new_bindings = list.map(syntax.to_binding, list.from(ast.grammar_.subs))
      local new = syntax.generate("new_grammar", table.unpack(new_bindings))
      new.new_grammar.text = ast.grammar_.text
      new.new_grammar.pos = ast.grammar_.pos
      new.new_grammar.replaces = ast
      return new
   elseif name=="local_" then
      local new = syntax.top_level_transform1(ast.local_.subs[1])
      return syntax.generate("local_", new)
   elseif (name=="syntax_error") then
      return ast				    -- errors will be culled out later
   elseif (name=="package_decl") or (name=="language_decl") or (name=="import_decl") then
      return ast				    -- no transformation needed
   else
      return syntax.expand_rhs(ast, (next(ast)))
   end
end

-- function syntax.replace_ref(ast, identifier, replacement_ast):
-- walk ast looking for ref nodes; replace each ref node for 'identifier' with replacement_ast
-- e.g.
    -- > pt, orig = parse_and_explain("foo")
    -- > table.print(pt)
    -- {1: {ref: 
    -- 	   {text: "foo", 
    -- 	    pos: 1}}}
    -- > table.print(syntax.replace_ref(pt[1], "foo", {blargh={pos=1,text="hello, world"}}))
    -- {blargh: 
    --    {pos: 1, 
    -- 	text: "hello, world"}}
    -- > table.print(syntax.replace_ref(pt[1], "bar", {blargh={pos=1,text="hello, world"}}))
    -- {ref: 
    --    {text: "foo", 
    -- 	pos: 1}}
    -- > 
syntax.replace_ref =
   syntax.make_transformer(function(ast, identifier, replacement_ast)
			      local ref_type, pos, ref_id = common.decode_match(ast)
			      assert(ref_type=="ref")
			      if ref_id==identifier then
				 return replacement_ast
			      else
				 return ast	    -- no change
			      end
			   end,
			   "ref",
			   true)

local function make_transformer(top_level_transformer)
   return function(astlist)
	     local new_astlist = {}
	     for i=1,#astlist do new_astlist[i] = top_level_transformer(astlist[i]); end
	     return new_astlist, astlist, {}		    -- last value is table of warnings
	  end
end

syntax.transform0 = make_transformer(syntax.top_level_transform0)
syntax.transform1 = make_transformer(syntax.top_level_transform1)

return syntax

