-- -*- Mode: Lua; -*-                                                                             
--
-- ast.lua    ast for Rosie Pattern Language
--
-- © Copyright IBM Corporation 2017.
-- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
-- AUTHOR: Jamie A. Jennings

local violation = require "violation"
local catch = violation.catch
local raise = violation.raise
local is_exception = violation.is_exception

local recordtype = require "recordtype"
local NIL = recordtype.NIL

local list = require "list"
local map = list.map; apply = list.apply; append = list.append; foreach = list.foreach; filter = list.filter

local ustring = require "ustring"

local not_atmosphere = common.not_atmosphere	    -- Predicate on ast type

local ast = {}

ast.block = recordtype.new("block",
			   {stmts = {};
			    block_pdecl = NIL;	    -- a pdecl (filled in during expansion)
			    block_ideclists = NIL;  -- list of ideclists (filled in during expansion)
			    pat = NIL;
			    sourceref = NIL;})

ast.binding = recordtype.new("binding",
			  {ref = NIL;
			   exp = NIL;
			   is_alias = false;
			   is_local = false;
			   pat = NIL;
			   sourceref = NIL;})

-- Update on the comment below: This is addressed in rpl_1_2.
  -- An rpl grammar is an *expression* in the ast, despite the fact that the rpl 1.1 syntax allows
  -- only grammar statements.  This unusual situation is due to the fact that we *want* grammars to
  -- be expressions so that:
  -- (1) they can be bound to identifiers different from the name of the start rule
  -- (2) they can be embedded (as literal expressions) in other expressions without first having to
  --     be bound to an identifier
  -- (3) and that includes being embedded into other grammars
  -- BUT, because the need for (2) and (3) are not obvious, we don't want to design their solutions
  -- or implement them now (in RPL 1.1).  We note that (2) will need a good concrete syntax, and (3)
  -- may require some lpeg gymnastics.  Clearly, more investigation is needed.
ast.grammar = recordtype.new("grammar",
			     {private_rules = {};
			      public_rules = {};
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

ast.and_exp = recordtype.new("and_exp",
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

ast.bracket = recordtype.new("bracket",		    -- [ [exp1] ... ]
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

ast.ldecl = recordtype.new("ldecl",		    -- language_decl
			   {version_spec = NIL;
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
	      ex.private_rules)
      foreach(function(rule)
		 rule.exp = ast.visit_expressions(rule.exp, predicate, fn)
	      end,
	      ex.public_rules)
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

local function raise_error(msg, sref, a)
   return raise(violation.syntax.new{who='parser',
				     message=msg,
				     sourceref=sref,
				     ast=a})
end

local convert_exp;

function ast.simple_charset_p(a)
   return (ast.cs_named.is(a) or
	   ast.cs_list.is(a) or
	   ast.cs_range.is(a))
end

local function flatten_exp(pt, pt_type)
   local function flatten(pt)
      if pt.type == "form.exp" then
	 assert(pt.subs)
	 local subs = filter(not_atmosphere, pt.subs)
	 assert(#subs==1)
	 pt = subs[1]
      end
      if pt.type == pt_type then
	 return apply(append, map(flatten, list.from(pt.subs)))
      else
	 return {pt}
      end
   end
   return flatten(pt)
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

function convert_bracket(pt, sref)
   sref = common.source.new{s=pt.s, e=pt.e, origin=sref.origin, text=sref.text, parent=sref.parent}
   assert(pt.type=="form.bracket")
   local exps, compflag

   exps = filter(not_atmosphere, pt.subs)
   assert(exps[1])
   compflag = (exps[1].type=="complement")
   if compflag then
      table.remove(exps, 1)
   end
   assert(exps[1] and (not exps[2]) and (exps[1].type=="form.exp"))
   exps = exps[1].subs
   assert(exps[1] and (not exps[2]))
   local cexp
   if exps[1].type=="form.sequence" then
      local explist = filter(not_atmosphere, flatten_exp(exps[1], "form.sequence"))
      cexp = ast.choice.new{exps = map(function(exp) return convert_exp(exp, sref) end,
				       explist),
			    sourceref=sref}
   else
      cexp = convert_exp(exps[1], sref)
   end
   return ast.bracket.new{cexp = cexp,
			  complement = compflag,
			  sourceref=sref}
end

local function process_raw_charlist(char_exps)
   local raw_chars = table.concat(map(function(sub) return sub.data; end, char_exps))
   local chars, offense = ustring.unescape_charlist(raw_chars)
   if not chars then return nil, offense; end
   local set = ustring.explode(chars)
   local seen = {}
   for _, char in ipairs(set) do
      if seen[char] then
	 return nil, "duplicate characters in character list: " .. ustring.escape(char)
      end
      seen[char] = true
   end
   return set
end
   
local function process_raw_char_range(first, last, sref)
   sref = common.source.new{s=sref.s, e=sref.e,
			    origin=sref.origin,
			    text=sref.text,
			    parent=sref.parent}
   local c1, offense = ustring.unescape_charlist(first.data)
   if (not c1) then
      sref.s = first.s; sref.e = first.e
      raise_error(offense, sref, first)
   end
   local c2, offense = ustring.unescape_charlist(last.data)
   if (not c2) then
      sref.s = last.s; sref.e = last.e
      raise_error(offense, sref, last)
   end
   local invalid_length_msg =
      "invalid character range edge (not a single character): "
   if (ustring.len(c1) ~= 1) then
      sref.s = first.s; sref.e = first.e
      raise_error(invalid_length_msg .. c1, sref, first)
   elseif (ustring.len(c2) ~= 1) then
      sref.s = last.s; sref.e = last.e
      raise_error(invalid_length_msg .. c2, sref, last)
   end
   return c1, c2
end

function convert_simple_charset(pt, sref)
   assert(sref)
   local exps = list.from(pt.subs or {})
   local compflag = exps[1] and exps[1].type=="complement"
   if compflag then
      exps = list.cdr(exps)
   end
   if pt.type=="named_charset" then
      return convert_cs_named(pt, sref)
   elseif pt.type=="charlist" then
      local chars, err = process_raw_charlist(exps)
      if not chars then raise_error(err, sref); end
      return ast.cs_list.new{chars = chars,
			     complement = compflag,
			     sourceref=sref}
   elseif pt.type=="range" then
      -- N.B. 'range_first', 'range_last' are part of RPL 1.1.  The core parser
      -- will produce sub-expressions of type 'character'.
      assert(exps[1].type=="range_first" or exps[1].type=="character")
      assert(exps[2].type=="range_last" or exps[2].type=="character")
      local c1, c2 = process_raw_char_range(exps[1], exps[2], sref)
      return ast.cs_range.new{first = c1,
			      last = c2,
			      complement = compflag,
			      sourceref=sref}
   
   else
      error("Internal error: do not know how to convert charset exp type: " .. tostring(pt.type))
   end
end

local function convert_quantified_exp(pt, subs, exp_converter, sref)
   local exp, q = subs[1], subs[2]
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
   if ast.sequence.is(ex) then
      return ast.cooked.new{exp=ex, sourceref=ex.sourceref}
   else
      return ex
   end
end

function ast.ambient_raw_exp(ex)
   assert(ex.sourceref)
   if not (ast.raw.is(ex) or ast.cooked.is(ex)) then
      if ast.sequence.is(ex) then
	 return ast.raw.new{exp=ex, sourceref=ex.sourceref}
      end
   end
   return ex
end

function convert_exp(pt, sref)
   local sref = common.source.new{s=pt.s, e=pt.e, origin=sref.origin, text=sref.text, parent=sref.parent}
   local subs = pt.subs and filter(not_atmosphere, pt.subs)
   local function convert1(pt)
      return convert_exp(pt, sref)
   end
   if pt.type=="form.binding" then
      raise(violation.syntax.new{who="parser",
				 message="found statement where expression was expected",
				 sourceref=sref,
				 ast=pt})
   elseif pt.type=="form.exp" then
      assert(subs and subs[1])
      return convert_exp(subs[1], sref)
   elseif pt.type=="form.term" then
      assert(subs and subs[1])
      if subs[2] then
	 return convert_quantified_exp(pt, subs, convert_exp, sref)
      else
	 return convert_exp(subs[1], sref)
      end
   elseif pt.type=="form.predicate" then
      return ast.predicate.new{type = subs[1].type,
			       exp = convert_exp(subs[2], sref),
			       sourceref=sref}
   elseif pt.type=="form.cooked" then
      return ast.cooked.new{exp = convert_exp(subs[1], sref),
			    sourceref=sref}
   elseif pt.type=="form.raw" then
      return ast.raw.new{exp = convert_exp(subs[1], sref), 
		      sourceref=sref}
   elseif pt.type=="form.choice" then
      return ast.choice.new{exps = map(convert1, filter(not_atmosphere, flatten_exp(pt, "form.choice"))),
			    sourceref=sref}
   elseif pt.type=="form.and_exp" then
      return ast.and_exp.new{exps = map(convert1, filter(not_atmosphere, flatten_exp(pt, "form.and_exp"))),
			     sourceref=sref}
   elseif pt.type=="form.sequence" then
      return ast.sequence.new{exps = map(convert1,
					 filter(not_atmosphere, flatten_exp(pt, "form.sequence"))),
			      sourceref=sref}
   elseif pt.type=="identifier" then
      return convert_identifier(pt, sref)
   elseif pt.type=="literal" then
      return ast.literal.new{value = pt.data, sourceref=sref}
   elseif pt.type=="hash_exp" then
      local val_ast = assert(subs and subs[1])
      if val_ast.type=="tag" then
	 return ast.hashtag.new{value = val_ast.data, sourceref=sref}
      elseif val_ast.type=="literal" then
	 return ast.string.new{value = val_ast.data, sourceref=sref}
      else
	 assert(false, "unexpected sub-match in hash_exp parse tree")
      end
   elseif pt.type=="named_charset" or pt.type=="charlist" or pt.type=="range" then
      return convert_simple_charset(pt, sref)
   elseif pt.type=="form.bracket" then
      return convert_bracket(pt, sref)
   elseif pt.type=="form.quantified_exp" then
      return convert_quantified_exp(pt, subs, convert_exp, sref)
   elseif pt.type=="form.application" then
      local id = subs[1]
      assert(id.type=="identifier")
      local arglist = subs[2]
      local operands = map(convert1, arglist.subs)
      if (arglist.type=="form.arglist") then
	 operands = map(ast.ambient_cook_exp, operands)
      elseif (arglist.type=="form.rawarglist") then
	 operands = map(ast.ambient_raw_exp, operands)
      else
	 assert(arglist.type=="form.arg")
	 assert(#arglist.subs==1)
      end
      return ast.application.new{ref=convert_identifier(id, sref),
			         arglist=operands,
			         sourceref=sref}
   elseif pt.type=="int" then
      local i = tonumber(pt.data)
      if not i then
	 -- FUTURE: tonumber() will return incorrect values when the argument cannot be contained
	 -- in a Lua integer.  We should trap this situation and throw an error.
	 assert(false, "parser allowed invalid integer: " .. tostring(pt.data))
      end
      return ast.int.new{value=i, sourceref=sref}
   elseif pt.type=="form.grammar_exp" then
      raise(violation.syntax.new{who="parser",
				 message="grammar expressions are not supported",
				 sourceref=sref,
				 ast=pt})
				 
   elseif pt.type=="form.let_exp" then
      raise(violation.syntax.new{who="parser",
				 message="let expressions are not supported",
				 sourceref=sref,
				 ast=pt})
				 
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
      importpath = ustring.dequote(importpath)
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
   local subs = pt.subs and filter(not_atmosphere, pt.subs)
   if pt.type=="form.exp" then
      raise(violation.syntax.new{who="parser",
				 message="found expression where statement was expected",
				 sourceref=sref,
				 ast=pt})
   elseif pt.type=="form.binding" then
      assert(subs and subs[1])
      return convert_stmt(subs[1], sref)
   elseif pt.type=="form.empty" then
      return false
   elseif pt.type=="form.simple" then
      assert(subs and subs[1] and subs[2])
      local alias_flag = false
      local local_flag = false
      if subs[1].type=="form.local_" then
	 local_flag = true
	 table.remove(subs, 1)
      end
      if subs[1].type=="form.alias_" then
	 alias_flag = true
	 table.remove(subs, 1)
      end
      return ast.binding.new{ref = convert_exp(subs[1], sref),
			     exp = convert_exp(subs[2], sref),
			     is_alias = alias_flag,
			     is_local = local_flag,
			     sourceref = sref}
   elseif pt.type=="form.grammar_block" then
      assert(subs and subs[1])
      assert(subs[1].type=="form.bindings")
      local private_bindings = subs[1].subs
      local public_bindings
      if subs[2] then
	 assert(subs[2].type=="form.bindings")
	 public_bindings = subs[2].subs
      else
	 public_bindings = subs[1].subs
	 private_bindings = {}
      end

--       if #private_bindings == 0 then
-- 	 if #public_bindings == 1 then
-- 	    print("******************************************************************")
-- 	    print("* Found an old-style grammar that will still work (1 binding)    *")
-- 	    print("******************************************************************")
-- 	 else
-- 	    print("******************************************************************")
-- 	    print("* More than one public binding... this will become an error      *")
-- 	    print("******************************************************************")
-- 	 end
--       end
      local function convert_rules(rules)
	 return filter(function(obj) return obj; end,	 
		       map(function(sub)
			      return convert_stmt(sub, sref)
			   end,
			   rules))
      end
      local private_rules = convert_rules(private_bindings)
      local public_rules = convert_rules(public_bindings)
      assert(public_rules and public_rules[1])
      local aliasflag = public_rules[1].is_alias
      local boundref = public_rules[1].ref
      local gexp = ast.grammar.new{private_rules = private_rules,
				   public_rules = public_rules,
				   sourceref = sref}
      return ast.binding.new{ref = boundref,
			     exp = gexp,
			     is_alias = aliasflag,
			     is_local = false}
   elseif pt.type=="package_decl" then
      assert(subs and subs[1])
      local pname = subs[1].data
      return ast.pdecl.new{name=pname, sourceref=sref}
   elseif pt.type=="import_decl" then
      local deps = expand_import_decl(pt)
      local function to_idecl(dep)
	 return ast.idecl.new{importpath = dep.importpath,
			      prefix = dep.prefix,
			      sourceref = sref}
      end
      return ast.ideclist.new{idecls = map(to_idecl, deps), sourceref=sref}
   elseif pt.type=="language_decl" then
      assert(subs and subs[1])
      assert(subs[1].type=="version_spec")
      local version_spec = subs[1].data
      return ast.ldecl.new{version_spec=version_spec, sourceref=sref}
   elseif pt.type=="form.let_block" then
      raise(violation.syntax.new{who="parser",
				 message="let statements are not supported",
				 sourceref=sref,
				 ast=pt})
				 
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
   local subs = pt.subs and filter(not_atmosphere, pt.subs)
   if pt.type=="rpl_expression" then
      assert(subs and subs[1] and (not subs[2]))
      return convert_exp(subs[1], source_record)
   elseif pt.type=="rpl_statements" or pt.type=="rpl_core" then
      local stmts = map(function(sub)
			   return convert_stmt(sub, source_record)
			end,
			subs or {})
      stmts = filter(function(obj) return obj end, stmts)
      return ast.block.new{stmts = stmts;
			   sourceref = source_record}
   else
      error("Internal error: do not know how to convert " .. tostring(pt.type))
   end
end

function ast.from_parse_tree(pt, sref, messages)
   local ok, result = catch(convert, pt, sref)
   if not ok then
      error("Internal error in ast module: " .. tostring(result))
   end
   if is_exception(result) then
      table.insert(messages, result[1])
      return false
   end
   return result
end
   

---------------------------------------------------------------------------------------------------
-- Convert a parse tree produced by the rpl core parser
---------------------------------------------------------------------------------------------------

function convert_core_charset_exp(pt, sref)
   assert(pt.type=="charset_exp")
   local cs_exps = map(function(exp) return convert_simple_charset(exp, sref) end, pt.subs)
   return ast.bracket.new{cexp = ast.choice.new{exps=cs_exps,
						sourceref=sref},
			  complement = false,	    -- complement not supported
			  sourceref=sref}
end

function convert_core_exp(pt, sref)
   local sref = common.source.new{s=pt.s, e=pt.e, origin=sref.origin, text=sref.text, parent=sref.parent}
   local function convert1(pt)
      return convert_core_exp(pt, sref)
   end
   if pt.type=="predicate" then
      return ast.predicate.new{type = pt.subs[1].type, exp = convert1(pt.subs[2]), sourceref=sref}
   elseif pt.type=="cooked" then
      return ast.cooked.new{exp = convert1(pt.subs[1]), sourceref=sref}
   elseif pt.type=="raw" then
      return ast.raw.new{exp = convert1(pt.subs[1]), sourceref=sref}
   elseif pt.type=="choice" then
      return ast.choice.new{exps = map(convert1, flatten_exp(pt, "choice")), sourceref=sref}
   elseif pt.type=="sequence" then
      return ast.sequence.new{exps = map(convert1, flatten_exp(pt, "sequence")), sourceref=sref}
   elseif pt.type=="identifier" then
      return ast.ref.new{localname=pt.data, sourceref=sref}
   elseif pt.type=="literal0" then
      local text = pt.data
      assert(text:sub(1,1)=='"' and text:sub(-1,-1)=='"', "literal not in quotes: " .. text)
      return ast.literal.new{value = pt.data:sub(2, -2), sourceref=sref}
   elseif pt.type=="charset_exp" then
      return convert_core_charset_exp(pt, sref)
   elseif pt.type=="named_charset0" then
      local text = pt.data
      assert(text:sub(1,2)=="[:" and text:sub(-2,-1)==":]")
      text = text:sub(3,-3)
      if text:sub(1,1)=="^" then
	 error("Internal error: rpl core does not support complemented named character sets")
      end
      return ast.cs_named.new{name = text, complement = false, sourceref=sref}      
   elseif pt.type=="quantified_exp" then
      local subs = pt.subs and filter(not_atmosphere, pt.subs)
      return convert_quantified_exp(pt, subs, convert_core_exp, sref)
   else
      error("Internal error: do not know how to convert " .. tostring(pt.type))
   end
end

local function convert_core_stmt(pt, sref)
   sref = common.source.new{s=pt.s, e=pt.e, origin=sref.origin, text=sref.text, parent=sref.parent}
   local subs = pt.subs
   if pt.type=="assignment_" then
      assert(subs and subs[1] and subs[2])
      return ast.binding.new{ref = convert_core_exp(subs[1], sref),
			     exp = convert_core_exp(subs[2], sref),
			     is_alias = false,
			     is_local = false,
			     sourceref=sref}
   elseif pt.type=="alias_" then
      return ast.binding.new{ref = convert_core_exp(subs[1], sref),
			     exp = convert_core_exp(subs[2], sref),
			     is_alias = true,
			     is_local = false,
			     sourceref=sref}
   elseif pt.type=="grammar_" then
      local rules = map(function(sub)
			   return convert_core_stmt(sub, sref)
			end,
			subs)
      assert(rules and rules[1])
      local lastrule = rules[#rules]
      table.remove(rules, #rules)
      local aliasflag = lastrule.is_alias
      local boundref = lastrule.ref
      local gexp = ast.grammar.new{public_rules = {lastrule},
				   private_rules = rules,
				   sourceref=sref}
      return ast.binding.new{ref = boundref,
			     exp = gexp,
			     is_alias = aliasflag,
			     is_local = false}
   elseif pt.type=="local_" then
      local b = convert_core_stmt(subs[1], sref)
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

function ast.from_core_parse_tree(pt, sref)
   local ok, result = catch(convert_core, pt, sref)
   if not ok then
      error("Internal error in core section of ast module: " .. tostring(result))
   end
   if is_exception(result) then
      error(violation.tostring(result[1]))
   end
   return result
end

---------------------------------------------------------------------------------------------------
-- Find all references in an ast where the ref has a non-nil packagename
---------------------------------------------------------------------------------------------------

function ast.dependencies_of(a)
   -- Until we have new use cases, this only works on pre-expansion ASTs, i.e. those produced by
   -- the compiler's parse_expression function. 
   if ast.block.is(a) then
      if #a.stmts==0 then			    -- e.g. parsing the empty string as rpl
	 return {}
      else
	 return apply(append, map(ast.dependencies_of, a.stmts))
      end
   elseif ast.grammar.is(a) then
      return apply(append, append(map(ast.dependencies_of, a.private_rules),
				  map(ast.dependencies_of, a.public_rules)))
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
   elseif ast.sequence.is(a) or ast.choice.is(a) or ast.and_exp.is(a) then
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
	   ast.hashtag.is(a) or
	   ast.string.is(a) or
	   ast.int.is(a) or
	   ast.bracket.is(a) or 
	   ast.cs_named.is(a) or
	   ast.cs_list.is(a) or
	   ast.cs_range.is(a) or
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

local predicate_name_table =
   { ["lookahead"] = ">",
     ["lookbehind"] = "<",
     ["negation"] = "!" }

function ast.tostring(a, already_grouped)
   if ast.block.is(a) then
      return ( (a.block_pdecl and (ast.tostring(a.block_pdecl) .. "\n") or "") ..
	       table.concat(map(ast.tostring, a.block_ideclists or {}), "\n") ..
	       table.concat(map(ast.tostring, a.stmts or {}), "\n") )
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
	       ((#a.private_rules > 0) and
	        table.concat(map(ast.tostring, a.private_rules), "\n\t") .. "\nin\n"
	        or "") ..
	       table.concat(map(ast.tostring, a.public_rules), "\n\t") ..
	       "\nend\n" )
   elseif ast.ref.is(a) then
      local lname = (a.localname ~= "*" and a.localname) or "<anonymous>"
      return common.compose_id{a.packagename, lname}
   elseif ast.sequence.is(a) then
      local pre = already_grouped and "" or "{"
      local post = already_grouped and "" or "}"
      if #a.exps==1 then
	 if ast.simple_charset_p(a.exps[1]) then
	    return ast.tostring(a.exps[1])
	 end
      end
      return pre .. table.concat(map(function(exp)
					return ast.tostring(exp, already_grouped)
				     end,
				     a.exps),
				 " ") .. post
   elseif ast.choice.is(a) then
      local pre = already_grouped and "" or "{"
      local post = already_grouped and "" or "}"
      local choices = map(ast.tostring, a.exps)
      assert(#choices > 0, "empty choice ast?")
      return pre .. table.concat(choices, " / ") .. post
   elseif ast.and_exp.is(a) then
      local pre = already_grouped and "" or "{"
      local post = already_grouped and "" or "}"
      return pre .. table.concat(map(ast.tostring, a.exps), " & ") .. post
   elseif ast.predicate.is(a) then
      local symbol = predicate_name_table[a.type] or "UNKNOWN PREDICATE "
      return symbol .. ast.tostring(a.exp)
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
      return '"' .. ustring.escape_string(a.value) .. '"'
   elseif ast.bracket.is(a) then
      return "[" .. (a.complement and "^" or "") .. ast.tostring(a.cexp, true) .. "]"
   elseif ast.cs_named.is(a) then
      return "[:" .. (a.complement and "^" or "") .. a.name .. ":]"
   elseif ast.cs_list.is(a) then
      return ( "[" ..
	       (a.complement and "^" or "") ..
	       ustring.escape_charlist(table.concat(a.chars, "")) ..
	       "]" )
   elseif ast.cs_range.is(a) then
      return ( "[" .. (a.complement and "^" or "") ..
	       ustring.escape_charlist(a.first) .. "-" .. ustring.escape_charlist(a.last) ..
	       "]" )
   elseif ast.cs_intersection.is(a) then
      return table.concat(map(ast.tostring(a.cexps)), "&&")
   elseif ast.cs_difference.is(a) then
      return ast.tostring(a.first) .. "-" .. ast.tostring(a.second)
   elseif ast.application.is(a) then
      local argstring
      if ( #a.arglist==1 and
	   (ast.ref.is(a.arglist[1]) or
	    ast.sequence.is(a.arglist[1]) or
	    ast.cooked.is(a.arglist[1]) or
	    ast.raw.is(a.arglist[1])) )	then
	 argstring = ast.tostring(a.arglist[1])
      else
	 argstring = "{" .. table.concat(map(ast.tostring, a.arglist), ", ") .. "}"
      end
      return ast.tostring(a.ref) .. ":" .. argstring
   elseif ast.hashtag.is(a) then
      return '#' .. a.value
   elseif ast.string.is(a) then
      return ustring.requote(a.value)
   elseif ast.int.is(a) then
      return tostring(a.value)
   elseif ast.ldecl.is(a) then
      return tostring(a.version_spec)
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
      error("Interal error: do not know how to print this ast: " .. a_string)
   end
end


return ast
