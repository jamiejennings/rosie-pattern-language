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
map = list.map; apply = list.apply; append = list.append;
local rpl_parser = require "rpl-parser"

local ast = {}

ast.exp = recordtype.new("exp",
			 {exp = NIL;
			  pos = NIL;
			  fin = NIL;})

ast.block = recordtype.new("block",
			   {stmts = {};
			    pos = NIL;
			    fin = NIL;})

ast.bind = recordtype.new("bind",
			  {ref = NIL;
			   exp = NIL;
			   is_alias = false;
			   is_local = false;
			   pos = NIL;
			   fin = NIL;})

ast.grammar = recordtype.new("grammar",
			     {rules = {};
			      pos = NIL;
			      fin = NIL;})

ast.ref = recordtype.new("ref",
			 {localname = NIL;
			  packagename = NIL;
			  pos = NIL;
			  fin = NIL;})

ast.seq = recordtype.new("seq",
			 {exps = {};
			  pos = NIL;
			  fin = NIL;})

ast.choice = recordtype.new("choice",
			    {exps = {};
			     pos = NIL;
			     fin = NIL;})

ast.pred = recordtype.new("pred",
			  {type = NIL;
			   exp = NIL;
			   pos = NIL;
			   fin = NIL;})

ast.rep = recordtype.new("rep",
			 {min = NIL;
			  max = NIL;
			  exp = NIL;
			  pos = NIL;
			  fin = NIL;})

ast.cook = recordtype.new("cook",
			  {exp = NIL;
			   pos = NIL;
			   fin = NIL;})

ast.raw = recordtype.new("raw",
			 {exp = NIL;
			  pos = NIL;
			  fin = NIL;})


ast.lit = recordtype.new("lit",			    -- interpolated string literals
			 {value = NIL;
			  pos = NIL;
			  fin = NIL;})

ast.cexp_or = recordtype.new("cexp_or",		    -- [ [exp1][exp2] ... ]
			     {complement = false;
			      cexps = {};
			      pos = NIL;
			      fin = NIL;})

ast.cexp_and = recordtype.new("cexp_and",	    -- [ [exp1]&&[exp2]&& ... ]
			      {complement = false;
			       cexps = {};
			       pos = NIL;
			       fin = NIL;})

ast.cexp_diff = recordtype.new("cexp_diff",	    -- [ [first]-[second] ]
			       {complement = false;
				first = NIL;
				second = NIL;
				pos = NIL;
				fin = NIL;})

ast.cs_named = recordtype.new("cs_named",	    -- [:name:]
			      {complement = false;
			       name = NIL;
			       pos = NIL;
			       fin = NIL;})

ast.cs_list = recordtype.new("cs_list",		    -- [abc12$]
			      {complement = false;
			       chars = {};
			       pos = NIL;
			       fin = NIL;})

ast.cs_range = recordtype.new("cs_range",	    -- [a-z]
			      {complement = false;
			       first = NIL;
			       last = NIL;
			       pos = NIL;
			       fin = NIL;})

-- ast.cap = recordtype.new("cap",
-- 			 {name = NIL;
-- 			  exp = NIL;})

ast.pdecl = recordtype.new("pdecl",
			   {name = NIL;
			    pos = NIL;
			    fin = NIL;})

ast.idecl = recordtype.new("idecl",
			   {importpath = NIL;
			    prefix = NIL;
			    pos = NIL;
			    fin = NIL;})

ast.ideclist = recordtype.new("ideclist",
			      {imports = {};
			       pos = NIL;
			       fin = NIL;})
			    
local convert_exp;

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
   
local function convert_quantified_exp(pt)
   local e, q = pt.subs[1], pt.subs[2]
   local qname = q.type
   assert(qname=="question" or qname=="star" or qname=="plus" or qname=="repetition")
   local min, max
   if qname=="repetition" then
      min = tonumber(q.subs[1].text)
      if #q.subs==1 then
	 max = min
      else
	 max = tonumber(q.subs[2].text)
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
   return ast.rep.new{min = min,
		      max = max,
		      exp = convert_exp(e),
		      pos=pos, fin=fin}
end

local function primitive_charset(pt)
   return (pt.type=="named_charset" or
	   pt.type=="charlist" or
	   pt.type=="range")
end

local function convert_char_exp(pt)
   assert(pt.subs and pt.subs[1])
   local exps = list.from(pt.subs)
   local compflag = (pt.subs[1].type=="complement")
   if compflag then
      exps = list.cdr(exps)
      assert(pt.subs[2])
   end
   if pt.type=="charset_exp" then
      assert(exps[1])
      if primitive_charset(exps[1]) then
	 assert(not compflag)			    -- grammar does not allow this
	 return convert_char_exp(exps[1])
      else
	 return ast.cexp_or.new{complement = compflag,
				cexps = map(convert_char_exp, exps), 
				pos=pos, fin=fin}
      end
   elseif pt.type=="charset_combiner" then
      assert(pt.subs and pt.subs[1] and pt.subs[2] and pt.subs[3] and (not pt.subs[4]))
      assert(pt.subs[2].type=="op" and pt.subs[2].subs and pt.subs[2].subs[1])
      local left = pt.subs[1]
      local op = pt.subs[2].subs[1].type
      local right = pt.subs[3]
      if op=="intersection" then
	 return ast.cexp_and.new{cexps = {convert_char_exp(left), convert_char_exp(right)}, pos=pos, fin=fin}
      elseif op=="difference" then
	 return ast.cexp_diff.new{cexps = {convert_char_exp(left), convert_char_exp(right)}, pos=pos, fin=fin}
      elseif op=="union" then
	 return ast.cexp_or.new{cexps = {convert_char_exp(left), convert_char_exp(right)}, pos=pos, fin=fin}	 
      else
	 error("Internal error: do not know how to convert charset op " .. tostring(op))
      end
   elseif pt.type=="named_charset" then
      return ast.cs_named.new{name = exps[1].text, complement = compflag, pos=pos, fin=fin}
   elseif pt.type=="charlist" then
      return ast.cs_list.new{chars = map(function(sub) return sub.text; end, exps),
			     complement = compflag,
			     pos=pos, fin=fin}
   elseif pt.type=="range" then
      return ast.cs_range.new{first = exps[1].text,
			      last = exps[2].text,
			      complement = compflag,
			      pos=pos, fin=fin}
   end
end

function convert_exp(pt)
   if pt.type=="capture" then
      return ast.cap.new{name = pt.subs[1].text, exp = convert_exp(pt.subs[2]), pos=pos, fin=fin}
--   elseif pt.type=="ref" then
--      return ast.ref.new{localname = pt.text, packagename = NIL, pos=pos, fin=fin}
--   elseif pt.type=="extref" then
--      return ast.ref.new{localname = pt.text, packagename = pt.subs[2].text, pos=pos, fin=fin}
   elseif pt.type=="predicate" then
      return ast.pred.new{type = pt.subs[1].text, exp = convert_exp(pt.subs[2]), pos=pos, fin=fin}
   elseif pt.type=="cooked" then
      return ast.cook.new{exp = convert_exp(pt.subs[1]), pos=pos, fin=fin}
   elseif pt.type=="raw" then
      return ast.raw.new{exp = convert_exp(pt.subs[1]), pos=pos, fin=fin}
   elseif pt.type=="choice" then
      return ast.choice.new{exps = map(convert_exp, flatten(pt, "choice")), pos=pos, fin=fin}
   elseif pt.type=="sequence" then
      return ast.seq.new{exps = map(convert_exp, flatten(pt, "sequence")), pos=pos, fin=fin}
   elseif pt.type=="identifier" then
      assert(pt.subs and pt.subs[1])
      local localname, packagename
      if pt.subs[1].type=="localname" then
	 localname = pt.subs[1].text
      else
	 assert(pt.subs[1].type=="packagename")
	 assert(pt.subs[2] and pt.subs[2].type=="localname")
	 packagename = pt.subs[1].text
	 localname = pt.subs[2].text
      end
      return ast.ref.new{localname = localname, packagename = packagename, pos=pos, fin=fin}
   elseif pt.type=="literal" then
      return ast.lit.new{value = pt.text, pos=pos, fin=fin}
   elseif pt.type=="charset_exp" then
      return convert_char_exp(pt)
   elseif pt.type=="quantified_exp" then
      return convert_quantified_exp(pt)
   else
      error("Internal error: do not know how to convert " .. tostring(pt.type))
   end
end

local function convert_stmt(pt)
   if pt.type=="assignment_" then
      assert(pt.subs and pt.subs[1] and pt.subs[2])
      return ast.bind.new{ref = convert_exp(pt.subs[1]),
			  exp = convert_exp(pt.subs[2]),
			  is_alias = false,
			  is_local = false,
			  pos=pos, fin=fin}
   elseif pt.type=="alias_" then
      return ast.bind.new{ref = convert_exp(pt.subs[1]),
			  exp = convert_exp(pt.subs[2]),
			  is_alias = true,
			  is_local = false,
			  pos=pos, fin=fin}
   elseif pt.type=="local_" then
      local b = convert_stmt(pt.subs[1])
      b.is_local = true
      return b
   elseif pt.type=="package_decl" then
      return ast.pdecl.new{name=pt.text, pos=pos, fin=fin}
   elseif pt.type=="import_decl" then
      local deps = {}
      rpl_parser.expand_import_decl(pt, deps)
      local function to_idecl(dep)
	 return ast.idecl.new{importpath = dep.importpath,
			      prefix = dep.prefix}
      end
      return ast.ideclist.new{imports = map(to_idecl, deps), pos=pos, fin=fin}
   else
      error("Internal error: do not know how to convert " .. tostring(pt.type))
   end
end

local function convert(pt)
   if pt.type=="rpl_expression" then
      return ast.exp.new{exp = convert_exp(pt.subs[1]), pos=pos, fin=fin}
   elseif pt.type=="rpl_statements" then
      return ast.block.new{stmts = map(convert_stmt, pt.subs or {}), pos=pos, fin=fin}
   else
      error("Internal error: do not know how to convert " .. tostring(pt.type))
   end
end

ast.from_parse_tree = convert

return ast
