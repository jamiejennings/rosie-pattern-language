-- -*- Mode: Lua; -*-                                                                             
--
-- ast.lua    ast crud for Rosie Pattern Language
--
-- © Copyright IBM Corporation 2017.
-- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
-- AUTHOR: Jamie A. Jennings

local recordtype = require "recordtype"
local NIL = recordtype.NIL
local list = require "list"
local map = list.map; apply = list.apply; append = list.append; foreach = list.foreach

local ast = {}

ast.block = recordtype.new("block",
			   {stmts = {};
			    pdecl = NIL;	    -- Filled in during expansion
			    ideclist = NIL;	    -- Filled in during expansion
			    pat = NIL;
			    sourceref = NIL;})

ast.binding = recordtype.new("binding",
			  {ref = NIL;
			   exp = NIL;
			   is_alias = false;
			   is_local = false;
			   pat = NIL;
			   sourceref = NIL;})

-- A grammar is an expression in the ast, despite the fact that in the concrete grammar for rpl
-- 1.1, the keyword 'grammar' introduces a binding of a name to a 'grammar expression'.
ast.grammar = recordtype.new("grammar",
			     {rules = {};
			      pat = NIL;
			      sourceref = NIL;})

ast.ref = recordtype.new("ref",
			 {localname = NIL;
			  packagename = NIL;
			  pat = NIL;
			  sourceref = NIL;})

ast.sequence = recordtype.new("sequence",
			 {exps = {};
			  pat = NIL;
			  sourceref = NIL;})

ast.choice = recordtype.new("choice",
			    {exps = {};
			     pat = NIL;
			     sourceref = NIL;})

ast.predicate = recordtype.new("predicate",
			  {type = NIL;
			   exp = NIL;
			   pat = NIL;
			   sourceref = NIL;})

ast.repetition = recordtype.new("repetition",
			 {min = NIL;
			  max = NIL;
			  exp = NIL;
			  cooked = false;
			  pat = NIL;
			  sourceref = NIL;})

ast.cooked = recordtype.new("cooked",
			  {exp = NIL;
			   pat = NIL;
			   sourceref = NIL;})

ast.raw = recordtype.new("raw",
			 {exp = NIL;
			  pat = NIL;
			  sourceref = NIL;})


ast.literal = recordtype.new("literal",			    -- interpolated string literals
			     {value = NIL;		    -- raw value, as seen in rpl source
			      pat = NIL;
			      sourceref = NIL;})

ast.cs_exp = recordtype.new("cs_exp",		    -- [ [exp1] ... ]
			  {complement = false;
			   cexp = {};
			   pat = NIL;
			   sourceref = NIL;})

ast.cs_named = recordtype.new("cs_named",	    -- [:name:]
			      {complement = false;
			       name = NIL;
			       pat = NIL;
			       sourceref = NIL;})

ast.cs_list = recordtype.new("cs_list",		    -- [abc12$]
			      {complement = false;
			       chars = {};
			       pat = NIL;
			       sourceref = NIL;})

ast.cs_range = recordtype.new("cs_range",	    -- [a-z]
			      {complement = false;
			       first = NIL;
			       last = NIL;
			       pat = NIL;
			       sourceref = NIL;})

ast.cs_union = recordtype.new("cs_union",	    -- [ [exp1] ... ]
				{cexps = {};
				 pat = NIL;
				 sourceref = NIL;})

ast.cs_intersection = recordtype.new("cs_intersection", -- [ [exp1]&&[exp2]&& ... ]
				       {cexps = {};
					pat = NIL;
					sourceref = NIL;})

ast.cs_difference = recordtype.new("cs_difference",	-- [ [first]-[second] ]
				     {first = NIL;
				      second = NIL;
				      pat = NIL;
				      sourceref = NIL;})

ast.application = recordtype.new("application",
				 {ref = NIL;
				  arglist = NIL;
				  pat = NIL;
				  sourceref = NIL;})

ast.int = recordtype.new("int",
			 {value = NIL;
			  pat = NIL;
			  sourceref = NIL;})

ast.pdecl = recordtype.new("pdecl",
			   {name = NIL;
			    pat = NIL;
			    sourceref = NIL;})

ast.idecl = recordtype.new("idecl",
			   {importpath = NIL;
			    prefix = NIL;
			    pat = NIL;
			    sourceref = NIL;})

ast.ideclist = recordtype.new("ideclist",
			      {idecls = {};
			       pat = NIL;
			       sourceref = NIL;})

-- 'ast.repetition' is transformed during expansion into expressions that use atmost and atleast.
-- An 'ast.atmost' node compiles to a peg that accepts between 0 and max copies of exp, inclusive.
ast.atmost = recordtype.new("atmost",
			    {max = NIL;
			     exp = NIL;
			     pat = NIL;
			     sourceref = NIL;})

-- An 'ast.atleast' node compiles to a peg that accepts at least min copies of exp, with no
-- maximum limit.
ast.atleast = recordtype.new("atleast",
			     {min = NIL;
			      exp = NIL;
			      pat = NIL;
			      sourceref = NIL;})

ast.string = recordtype.new("string",			    -- interpolated string literals
			    {value = NIL;		    -- raw value, before interpolation
			     pat = NIL;
			     sourceref = NIL;})

ast.hashtag = recordtype.new("hashtag",
			      {value = NIL;
			       pat = NIL;
			       sourceref = NIL;})

---------------------------------------------------------------------------------------------------
-- Utility to visit each expression in an AST
---------------------------------------------------------------------------------------------------

-- When predicate(ex) is true, return fn(ex) else return ex.
-- Do this over all the general expressions in the ast.  Character set sub-expressions don't count.
function ast.visit_expressions(ex, predicate, fn)
   if predicate(ex) then return fn(ex)
   elseif ast.cooked.is(ex) or ast.raw.is(ex) or ast.predicate.is(ex) or ast.repetition.is(ex) then
      ex.exp = ast.visit_expressions(ex.exp, predicate, fn)
   elseif ast.choice.is(ex) or ast.sequence.is(ex) then
      ex.exps = map(function(ex) return ast.visit_expressions(ex, predicate, fn); end, ex.exps)
      assert(#ex.exps > 0)
   elseif ast.grammar.is(ex) then
      foreach(function(rule)
		 rule.exp = ast.visit_expressions(rule.exp, predicate, fn)
	      end,
	      ex.rules)
   elseif ast.application.is(ex) then
      ex.arglist.args = map(function(ex) return ast.visit_expressions(ex, predicate, fn); end,
			 ex.arglist.args)
   end
   -- No other ast type has a sub-expression to process
   return ex
end

---------------------------------------------------------------------------------------------------
-- Convert a parse tree into an ast
---------------------------------------------------------------------------------------------------

local convert_exp;

function ast.simple_charset_p(a)
   return (ast.cs_named.is(a) or
	   ast.cs_list.is(a) or
	   ast.cs_range.is(a))
end

local function flatten(pt, pt_type)
   local function flatten(pt)
      if pt.type == pt_type then
	 return apply(append, map(flatten, list.from(pt.subs)))
      else
	 return {pt}
      end
   end
   return flatten(pt)
end

local function flatten_cexp_in_place(a, target_type)
   local function lift(exps)
      if list.null(exps) then return list.from({}); end
      local first = exps[1]
      local lift1
      if target_type.is(first) then
	 local subs = list.from(first.cexps)
	 lift1 = lift(subs)
      else
	 flatten_cexp_in_place(first, target_type)
	 lift1 = list.new(first)
      end
      return append(lift1, lift(list.cdr(exps)))
   end
   if target_type.is(a) then
      local exps = list.from(a.cexps)
      a.cexps = lift(exps)
   elseif ast.cs_intersection.is(a) or ast.cs_union.is(a) then
      list.foreach(function(exp) flatten_cexp_in_place(exp, target_type) end, a.cexps)
   elseif ast.cs_exp.is(a) then
      flatten_cexp_in_place(a.cexp, target_type)
   elseif ast.cs_difference.is(a) then
      flatten_cexp_in_place(a.first, target_type)
      flatten_cexp_in_place(a.second, target_type)
   else
      -- else we have a "simple" cexp, which has no cexps inside it
      assert(ast.simple_charset_p(a))
   end
end

local convert_char_exp;

local function infix_to_prefix(exps, sref)
   -- exps := exp (op exp)*
   assert(sref)
   local rest = list.from(exps)
   local first = rest[1]
   local op = rest[2]
   if not op then return convert_char_exp(first, sref); end
   local optype = op.subs[1].type
   assert(optype)
   rest = list.cdr(list.cdr(rest))
   if optype=="intersection" then
      return ast.cs_intersection.new{cexps = {convert_char_exp(first, sref),
					      infix_to_prefix(rest, sref)},
				     sourceref=sref}
   elseif optype=="difference" then
      return ast.cs_difference.new{first = convert_char_exp(first, sref),
				   second = infix_to_prefix(rest, sref),
				   sourceref=sref}
   elseif optype=="union" then
      return ast.cs_union.new{cexps = {convert_char_exp(first, sref), 
				       infix_to_prefix(rest, sref)}, 
			      sourceref=sref}
   else
      error("Internal error: do not know how to convert charset op " .. tostring(optype))
   end
end

local function convert_cs_named(pt, sref)
   assert(sref)
   assert(pt.subs and pt.subs[1])
   sref = common.source.new{s=pt.s, e=pt.e, origin=sref.origin, text=sref.text, parent=sref.parent}
   local name = pt.subs[1].data
   local compflag = (pt.subs[1].type=="complement")
   if compflag then
      assert(pt.subs[2])
      name = pt.subs[2].data
   end
   return ast.cs_named.new{name = name,
			   complement = compflag,
			   sourceref=sref}
end

function convert_char_exp(pt, sref)
   sref = common.source.new{s=pt.s, e=pt.e, origin=sref.origin, text=sref.text, parent=sref.parent}
   local exps, compflag
   if pt.type=="charset_exp" then
      assert(pt.subs and pt.subs[1])
      pt = pt.subs[1]
      exps = list.from(pt.subs)
      compflag = (pt.subs[1].type=="complement")
      if compflag then
	 exps = list.cdr(exps)
	 assert(pt.subs[2])
      end
   else
      -- We have something that appeared inside a charset_exp.
      exps = list.from(pt.subs)
      compflag = false
   end
   if pt.type=="named_charset" then
      return convert_cs_named(pt, sref)
   elseif pt.type=="charlist" then
      return ast.cs_list.new{chars = map(function(sub) return sub.data; end, exps),
			     complement = compflag,
			     sourceref=sref}
   elseif pt.type=="range" then
      return ast.cs_range.new{first = exps[1].data,
			      last = exps[2].data,
			      complement = compflag,
			      sourceref=sref}
   elseif pt.type=="compound_charset" then
      assert(exps[1])
      local prefix_cexp
      if not exps[2] then
	 -- There is only one charset expression inside the compound charset
	 local cexp = convert_char_exp(exps[1], sref)
	 if compflag then cexp.complement = not cexp.complement; end
	 return cexp
      end
      prefix_cexp = infix_to_prefix(exps, sref)
      flatten_cexp_in_place(prefix_cexp, ast.cs_intersection)
      flatten_cexp_in_place(prefix_cexp, ast.cs_union)
      return ast.cs_exp.new{cexp = prefix_cexp,
			    complement = compflag,
			    sourceref=sref}
   else
      error("Internal error: do not know how to convert charset exp type: " .. tostring(pt.type))
   end
end

local function convert_quantified_exp(pt, exp_converter, sref)
   local exp, q = pt.subs[1], pt.subs[2]
   local qname = q.type
   sref = common.source.new{s=pt.s, e=pt.e, origin=sref.origin, text=sref.text, parent=sref.parent}
   assert(qname=="question" or qname=="star" or qname=="plus" or qname=="repetition")
   local min, max
   if qname=="repetition" then
      min = tonumber(q.subs[1].data)
      if #q.subs==1 then
	 max = min
      else
	 max = tonumber(q.subs[2].data)
      end
   elseif qname=="question" then
      min = 0
      max = 1
   elseif qname=="plus" then
      min = 1
   elseif qname=="star" then
      min = 0
   else
      error("Internal error: do not know how to convert quantifier " .. tostring(qname))
   end
   return ast.repetition.new{min = min,
			     max = max,
			     exp = exp_converter(exp, sref),
			     sourceref=sref}
end

local function convert_identifier(pt, sref)
   assert(pt.subs and pt.subs[1])
   sref = common.source.new{s=pt.s, e=pt.e, origin=sref.origin, text=sref.text, parent=sref.parent}
   local localname, packagename
   if pt.subs[1].type=="localname" then
      localname = pt.subs[1].data
   else
      assert(pt.subs[1].type=="packagename")
      assert(pt.subs[2] and pt.subs[2].type=="localname")
      packagename = pt.subs[1].data
      localname = pt.subs[2].data
   end
   return ast.ref.new{localname=localname, packagename=packagename, sourceref=sref}
end   

-- The ambient "atmosphere" in rpl is that sequences are cooked unless explicitly marked as raw.
-- 'ambient_cook' wraps the rhs of bindings in an explicit 'cooked' ast unless the expression is
-- already explicitly cooked or raw.  
function ast.ambient_cook_exp(ex)
   assert(ex.sourceref)
--   if not (ast.raw.is(ex) or ast.cooked.is(ex)) then
   if ast.sequence.is(ex) then
      return ast.cooked.new{exp=ex, sourceref=ex.sourceref}
   else
      return ex
   end
end

function ast.ambient_raw_exp(ex)
   assert(ex.sourceref)
   if not (ast.raw.is(ex) or ast.cooked.is(ex)) then
      return ast.raw.new{exp=ex, sourceref=ex.sourceref}
   else
      return ex
   end
end

function convert_exp(pt, sref)
   local sref = common.source.new{s=pt.s, e=pt.e, origin=sref.origin, text=sref.text, parent=sref.parent}
   local function convert1(pt)
      return convert_exp(pt, sref)
   end
   if pt.type=="capture" then
      return ast.cap.new{name = pt.subs[1].data,
			 exp = convert_exp(pt.subs[2], sref),
		         sourceref=sref}
   elseif pt.type=="predicate" then
      return ast.predicate.new{type = pt.subs[1].data,
			       exp = convert_exp(pt.subs[2], sref),
			       sourceref=sref}
   elseif pt.type=="cooked" then
      return ast.cooked.new{exp = convert_exp(pt.subs[1], sref),
			    sourceref=sref}
   elseif pt.type=="raw" then
      return ast.raw.new{exp = convert_exp(pt.subs[1], sref), 
		      sourceref=sref}
   elseif pt.type=="choice" then
      return ast.choice.new{exps = map(convert1, flatten(pt, "choice")), sourceref=sref}
   elseif pt.type=="sequence" then
      return ast.sequence.new{exps = map(convert1, flatten(pt, "sequence")), sourceref=sref}
   elseif pt.type=="identifier" then
      return convert_identifier(pt, sref)
   elseif pt.type=="literal" then
      return ast.literal.new{value = pt.data, sourceref=sref}
   elseif pt.type=="hash_exp" then
      local val_ast = assert(pt.subs and pt.subs[1])
      if val_ast.type=="tag" then
	 return ast.hashtag.new{value = val_ast.data, sourceref=sref}
      elseif val_ast.type=="literal" then
	 return ast.string.new{value = val_ast.data, sourceref=sref}
      else
	 assert(false, "unexpected sub-match in hash_exp parse tree")
      end
   elseif pt.type=="charset_exp" then
      return convert_char_exp(pt, sref)
   elseif pt.type=="quantified_exp" then
      return convert_quantified_exp(pt, convert_exp, sref)
   elseif pt.type=="application" then
      local id = pt.subs[1]
      assert(id.type=="identifier")
      local arglist = pt.subs[2]
      local operands = map(convert1, arglist.subs)
      if (arglist.type=="arglist") then
	 operands = map(ast.ambient_cook_exp, operands)
      elseif (arglist.type=="rawarglist") then
	 operands = map(ast.ambient_raw_exp, operands)
      else
	 assert(arglist.type=="arg")
	 assert(#arglist.subs==1)
      end
      return ast.application.new{ref=convert_identifier(id, sref),
			         arglist=operands,
			         sourceref=sref}
   else
      error("Internal error: do not know how to convert " .. tostring(pt.type))
   end
end

-- expand_import_decl takes a single import decl parse node and expands it into a list of as many
-- individual import declarations as it contains.  
local function expand_import_decl(decl_parse_node)
   local results = {}
   local decode_match = common.decode_match
   local typ, pos, text, specs, fin = decode_match(decl_parse_node)
   assert(typ=="import_decl")
   assert(type(results)=="table")
   for _,spec in ipairs(specs) do
      local importpath, prefix
      local typ, pos, text, subs, fin = decode_match(spec)
      assert(subs and subs[1], "missing package name to import?")
      local typ, pos, importpath = decode_match(subs[1])
      importpath = common.dequote(importpath)
      common.note("*\t", "import |", importpath, "|")
      if subs[2] then
	 typ, pos, prefix = decode_match(subs[2])
	 assert(typ=="packagename" or typ=="dot")
	 common.note("\t  as ", prefix)
      end
      table.insert(results, {importpath=importpath, prefix=prefix})
   end -- for each importspec in the import_decl
   return results
end

local function convert_stmt(pt, sref)
   sref = common.source.new{s=pt.s, e=pt.e, origin=sref.origin, text=sref.text, parent=sref.parent}
   if pt.type=="assignment_" then
      assert(pt.subs and pt.subs[1] and pt.subs[2])
      return ast.binding.new{ref = convert_exp(pt.subs[1], sref),
			  exp = convert_exp(pt.subs[2], sref),
			  is_alias = false,
			  is_local = false,
		          sourceref = sref}
   elseif pt.type=="alias_" then
      return ast.binding.new{ref = convert_exp(pt.subs[1], sref),
			  exp = convert_exp(pt.subs[2], sref),
			  is_alias = true,
			  is_local = false,
		          sourceref = sref}
   elseif pt.type=="grammar_" then
      local rules = map(function(sub)
			   return convert_stmt(sub, sref)
			end,
			pt.subs)
      assert(rules and rules[1])
      local aliasflag = rules[1].is_alias
      local boundref = rules[1].ref
      local gexp = ast.grammar.new{rules = rules, sourceref = sref}
      return ast.binding.new{ref = boundref,
			     exp = gexp,
			     is_alias = aliasflag,
			     is_local = false}
   elseif pt.type=="local_" then
      local b = convert_stmt(pt.subs[1], sref)
      b.is_local = true
      return b
   elseif pt.type=="package_decl" then
      assert(pt.subs and pt.subs[1])
      local pname = pt.subs[1].data
      return ast.pdecl.new{name=pname, sourceref=sref}
   elseif pt.type=="import_decl" then
      local deps = expand_import_decl(pt)
      local function to_idecl(dep)
	 return ast.idecl.new{importpath = dep.importpath,
			      prefix = dep.prefix,
			      sourceref = sref}
      end
      return ast.ideclist.new{idecls = map(to_idecl, deps), sourceref=sref}
   else
      error("Internal error: do not know how to convert " .. tostring(pt.type))
   end
end

local function convert(pt, source_record)
   assert(type(pt)=="table")
   assert(common.source.is(source_record))
   local source = source_record.text
   local origin = source_record.origin
   assert(type(source)=="string")
   assert(origin==nil or common.loadrequest.is(origin))
   if pt.type=="rpl_expression" then
      assert(pt.subs and pt.subs[1] and (not pt.subs[2]))
      return convert_exp(pt.subs[1], source_record)
   elseif pt.type=="rpl_statements" or pt.type=="rpl_core" then
      return ast.block.new{stmts = map(function(sub)
					  return convert_stmt(sub, source_record)
				       end,
				       pt.subs or {}),
			   sourceref = source_record}
   else
      error("Internal error: do not know how to convert " .. tostring(pt.type))
   end
end

ast.from_parse_tree = convert

---------------------------------------------------------------------------------------------------
-- Convert a parse tree produced by the rpl core parser
---------------------------------------------------------------------------------------------------

function convert_core_exp(pt, sref)
   local sref = common.source.new{s=pt.s, e=pt.e, origin=sref.origin, text=sref.text, parent=sref.parent}
   local function convert1(pt)
      return convert_core_exp(pt, sref)
   end
   if pt.type=="capture" then
      return ast.cap.new{name = pt.subs[1].data, exp = convert1(pt.subs[2]), sourceref=sref}
   elseif pt.type=="predicate" then
      return ast.predicate.new{type = pt.subs[1].data, exp = convert1(pt.subs[2]), sourceref=sref}
   elseif pt.type=="cooked" then
      return ast.cooked.new{exp = convert1(pt.subs[1]), sourceref=sref}
   elseif pt.type=="raw" then
      return ast.raw.new{exp = convert1(pt.subs[1]), sourceref=sref}
   elseif pt.type=="choice" then
      return ast.choice.new{exps = map(convert1, flatten(pt, "choice")), sourceref=sref}
   elseif pt.type=="sequence" then
      return ast.sequence.new{exps = map(convert1, flatten(pt, "sequence")), sourceref=sref}
   elseif pt.type=="identifier" then
      return ast.ref.new{localname=pt.data, sourceref=sref}
   elseif pt.type=="literal0" then
      local text = pt.data
      assert(text:sub(1,1)=='"' and text:sub(-1,-1)=='"', "literal not in quotes: " .. text)
      return ast.literal.new{value = pt.data:sub(2, -2), sourceref=sref}
   elseif pt.type=="charset_exp" then
      return convert_char_exp(pt, sref)
   elseif pt.type=="named_charset0" then
      local text = pt.data
      assert(text:sub(1,2)=="[:" and text:sub(-2,-1)==":]")
      text = text:sub(3,-3)
      if text:sub(1,1)=="^" then
	 error("Internal error: rpl core does not support complemented named character sets")
      end
      return ast.cs_named.new{name = text, complement = compflag, sourceref=sref}      
   elseif pt.type=="quantified_exp" then
      return convert_quantified_exp(pt, convert_core_exp, sref)
   else
      error("Internal error: do not know how to convert " .. tostring(pt.type))
   end
end

local function convert_core_stmt(pt, sref)
   sref = common.source.new{s=pt.s, e=pt.e, origin=sref.origin, text=sref.text, parent=sref.parent}
   if pt.type=="assignment_" then
      assert(pt.subs and pt.subs[1] and pt.subs[2])
      return ast.binding.new{ref = convert_core_exp(pt.subs[1], sref),
			  exp = convert_core_exp(pt.subs[2], sref),
			  is_alias = false,
			  is_local = false,
		          sourceref=sref}
   elseif pt.type=="alias_" then
      return ast.binding.new{ref = convert_core_exp(pt.subs[1], sref),
			  exp = convert_core_exp(pt.subs[2], sref),
			  is_alias = true,
			  is_local = false,
			  sourceref=sref}
   elseif pt.type=="grammar_" then
      local rules = map(function(sub)
			   return convert_core_stmt(sub, sref)
			end,
			pt.subs)
      assert(rules and rules[1])
      local aliasflag = rules[1].is_alias
      local boundref = rules[1].ref
      local gexp = ast.grammar.new{rules = rules,
				   sourceref=sref}
      return ast.binding.new{ref = boundref,
			  exp = gexp,
			  is_alias = aliasflag,
			  is_local = false}
   elseif pt.type=="local_" then
      local b = convert_core_stmt(pt.subs[1], sref)
      b.is_local = true
      return b
   elseif pt.type=="fake_package" then
      return ast.pdecl.new{name=".", sourceref=sref}
   elseif pt.type=="import_decl" then
      error("Internal error: core rpl does not support import declarations")
   else
      error("Internal error: do not know how to convert " .. tostring(pt.type))
   end
end

local function convert_core(pt, source_record)
   assert(type(pt)=="table")
   assert(common.source.is(source_record))
   local source = source_record.text
   local origin = source_record.origin
   assert(type(source)=="string")
   assert(origin==nil or common.loadrequest.is(origin))
   if pt.type=="rpl_expression" then
      assert(pt.subs and pt.subs[1] and (not pt.subs[2]))
      return convert_core_exp(pt.subs[1], source_record)
   elseif pt.type=="rpl_core" then
      return ast.block.new{stmts = map(function(sub)
					  return convert_core_stmt(sub, source_record)
				       end,
				       pt.subs or {}),
			   sourceref=source_record}
   else
      error("Internal error: do not know how to convert " .. tostring(pt.type))
   end
end

ast.from_core_parse_tree = convert_core

---------------------------------------------------------------------------------------------------
-- Find all references in an ast where the ref has a non-nil packagename
---------------------------------------------------------------------------------------------------

function ast.dependencies_of(a)
   -- Until we have new use cases, this only works on non-grammar expressions.  And it only works
   -- on pre-expansion ASTs, i.e. those produced by the compiler's parse_expression function.
   if ast.block.is(a) then
      return apply(append, map(ast.dependencies_of, a.stmts))
   elseif ast.grammar.is(a) then
      return apply(append, map(ast.dependencies_of, a.rules))
   elseif ast.binding.is(a) then
      return ast.dependencies_of(a.exp)
   elseif ast.ideclist.is(a) then
      return {}
   elseif ast.ref.is(a) then
      if a.packagename then
	 return {a.packagename}
      else
	 return {}
      end
   elseif ast.sequence.is(a) or ast.choice.is(a) then
      return apply(append, map(ast.dependencies_of, a.exps))
   elseif ast.application.is(a) then
      return apply(append, map(ast.dependencies_of, a.arglist))
   elseif (ast.predicate.is(a) or
	   ast.atleast.is(a) or
	   ast.atmost.is(a) or
	   ast.repetition.is(a) or
	   ast.cooked.is(a) or
	   ast.raw.is(a)) then
      return ast.dependencies_of(a.exp)
   elseif (ast.literal.is(a) or
	   ast.cs_exp.is(a) or 
	   ast.cs_named.is(a) or
	   ast.cs_list.is(a) or
	   ast.cs_range.is(a) or
	   ast.cs_union.is(a) or
	   ast.cs_intersection.is(a) or
	   ast.cs_difference.is(a)) then
      return {}
   else
      assert(false, "ast.dependencies_of received an unexpected ast type: " .. tostring(a))
   end
end
      
---------------------------------------------------------------------------------------------------
-- Reconstruct valid RPL from an ast
---------------------------------------------------------------------------------------------------

function ast.tostring(a, already_grouped)
   if ast.block.is(a) then
      return ( (a.pdecl and (ast.tostring(a.pdecl) .. "\n") or "") ..
	       (a.ideclist and ast.tostring(a.ideclist) or "") ..
	       table.concat(map(ast.tostring, a.stmts), "\n") )
   elseif ast.pdecl.is(a) then
      return "package " .. a.name .. "\n"
   elseif ast.idecl.is(a) then
      return "import " .. a.importpath .. (a.prefix and (" as " .. a.prefix) or "") .. "\n"
   elseif ast.ideclist.is(a) then
      return table.concat(map(ast.tostring, a.idecls), "\n")
   elseif ast.binding.is(a) then
      return ( (a.is_local and "local " or "") ..
	       (a.is_alias and "alias " or "") ..
	       ast.tostring(a.ref) .. " = " .. ast.tostring(a.exp) )
   elseif ast.grammar.is(a) then
      return ( "\ngrammar\n\t" ..
	       table.concat(map(ast.tostring, a.rules), "\n\t") ..
	       "\nend\n" )
   elseif ast.ref.is(a) then
      local lname = (a.localname ~= "*" and a.localname) or "<anonymous>"
      return ( (a.packagename and (a.packagename ~= ".") and (a.packagename .. ".") or "") .. lname )
   elseif ast.sequence.is(a) then
      local pre = already_grouped and "" or "{"
      local post = already_grouped and "" or "}"
      return pre .. table.concat(map(ast.tostring, a.exps), " ") .. post
   elseif ast.choice.is(a) then
      local pre = already_grouped and "" or "{"
      local post = already_grouped and "" or "}"
      local choices = map(ast.tostring, a.exps)
      assert(#choices > 0, "empty choice ast?")
      return pre .. table.concat(choices, " / ") .. post
   elseif ast.predicate.is(a) then
      return a.type .. ast.tostring(a.exp)
   elseif ast.repetition.is(a) then		    -- Before syntax expansion,
      local postfix				    -- this ast can be seen.
      if (not a.max) then
	 if a.min==0 then postfix = "*"
	 elseif a.min==1 then postfix = "+"
	 else postfix = "{" .. tostring(a.min) .. ",}"
	 end
      elseif (not a.min) and (a.max==1) then postfix = "?"
      else
	 postfix = "{" .. tostring(a.min) .. "," .. tostring(a.max) .. "}"
      end
      return ast.tostring(a.exp) .. postfix
   elseif ast.atleast.is(a) then		    -- After syntax expansion,
      local quantifier				    -- this ast can be seen.
      if a.min==0 then quantifier = "*"
      elseif a.min==1 then quantifier = "+"
      else quantifier = "{" .. tostring(a.min) .. ",}"; end
      local exp = ast.tostring(a.exp)
      if exp:sub(1,1)~="{" then exp = "{" .. exp .. "}"; end
      return exp .. quantifier
   elseif ast.atmost.is(a) then			    -- After syntax expansion,
      local exp = ast.tostring(a.exp)		    -- this ast can be seen.
      if exp:sub(1,1)~="{" then exp = "{" .. exp .. "}"; end
      local postfix = (a.max==1) and "?" or "{," .. tostring(a.max) .. "}"
      return exp .. postfix
   elseif ast.cooked.is(a) then
      return "(" .. ast.tostring(a.exp, true) .. ")"
   elseif ast.raw.is(a) then
      return "{" .. ast.tostring(a.exp, true) .. "}"
   elseif ast.literal.is(a) then
      return '"' .. a.value .. '"'
   elseif ast.cs_exp.is(a) then
      return "[" .. (a.complement and "^" or "") .. ast.tostring(a.cexp) .. "]"
   elseif ast.cs_named.is(a) then
      return "[:" .. (a.complement and "^" or "") .. a.name .. ":]"
   elseif ast.cs_list.is(a) then
      return ( "[" ..
	       (a.complement and "^" or "") ..
	       table.concat(a.chars, "") ..
	       "]" )
   elseif ast.cs_range.is(a) then
      return ( "[" .. (a.complement and "^" or "") ..
	       a.first .. "-" .. a.last ..
	       "]" )
   elseif ast.cs_union.is(a) then
      return table.concat(map(ast.tostring, a.cexps), " ")
   elseif ast.cs_intersection.is(a) then
      return table.concat(map(ast.tostring(a.cexps)), "&&")
   elseif ast.cs_difference.is(a) then
      return ast.tostring(a.first) .. "-" .. ast.tostring(a.second)
   elseif ast.application.is(a) then
      local argstring
      if ( #a.arglist==1 and
	   (ast.ref.is(a.arglist[1]) or
	    ast.cooked.is(a.arglist[1]) or
	    ast.raw.is(a.arglist[1])) )	then
	 argstring = ast.tostring(a.arglist[1])
      else
	 argstring = "(" .. table.concat(map(ast.tostring, a.arglist), ", ") .. ")"
      end
      return ast.tostring(a.ref) .. ":" .. argstring
   elseif list.is(a) then
      return tostring(map(ast.tostring, a))
   else
      local a_string = tostring(a)
      if type(a)=="table" and (not recordtype.parent(a)) then
	 a_string = a_string .. "\n"
	 for k,v in pairs(a) do
	    a_string = a_string .. tostring(k) .. ": " .. tostring(v) .. "\n"
	 end
      end
      error("do not know how to print this ast: " .. a_string)
   end
end


return ast
