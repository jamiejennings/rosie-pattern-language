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

local ast = {}

ast.exp = recordtype.new("exp",
			 {exp = NIL;
			  pos = NIL;
			  fin = NIL;})

ast.block = recordtype.new("block",
			   {stmnts = {};
			    pos = NIL;
			    fin = NIL;})

ast.bind = recordtype.new("bind",
			  {id = NIL;
			   exp = NIL;
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

ast.cap = recordtype.new("cap",
			 {name = NIL;
			  exp = NIL;})

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

end

local function convert_char_exp(pt)
   assert(pt.subs and pt.subs[1])
   local exps = list.from(pt.subs)
   local comp = (exp.subs[1].type=="complement")
   if comp then
      exps = list.cdr(exps)
      assert(exp.subs[2])
   end
   if exp.type=="charset_exp" then
      return map(convert_char_exp, exps)
   -- elseif exp.type=="op" then
   --    if exp.subs[1].type=="intersection" then
   -- 	 return ast.cexp_and(complement = comp,
   -- 			     cexps = 
   else
      local char = "#'"
      if exp.type=="named_charset" then char = ""; end
      local exps_str = table.concat(list.map(function(a) return char .. a.text end, exps), " ")
      return start .. exps_str .. finish
   end
end

local function convert_exp(pt)
   if pt.type=="capture" then
      return ast.cap{name = pt.subs[1].text, exp =pt.subs[2], pos=pos, fin=fin}
--   elseif pt.type=="ref" then
--      return ast.ref{localname = pt.text, packagename = NIL, pos=pos, fin=fin}
--   elseif pt.type=="extref" then
--      return ast.ref{localname = pt.text, packagename = pt.subs[2].text, pos=pos, fin=fin}
   elseif pt.type=="predicate" then
      return ast.pred{type = pt.subs[1].text, exp = pt.subs[2], pos=pos, fin=fin}
   elseif pt.type=="cooked" then
      return ast.cook{exp = pt.subs[1], pos=pos, fin=fin}
   elseif pt.type=="raw" then
      return ast.raw{exp = pt.subs[1], pos=pos, fin=fin}
   elseif pt.type=="choice" then
      return ast.choice{exps = flatten(pt.subs, "choice"), pos=pos, fin=fin}
   elseif pt.type=="sequence" then
      return ast.seq{exps = flatten(pt.subs, "sequence"), pos=pos, fin=fin}
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
      return ast.ref{localname = localname, packagename = packagename, pos=pos, fin=fin}
   elseif pt.type=="literal" then
      return ast.lit{value = pt.text, pos=pos, fin=fin}
   elseif pt.type=="charset_exp" then
      return convert_charset(pt)
   elseif pt.type=="quantified_exp" then
      return convert_quantified_exp(pt)
   else
      error("Internal error: do not know how to convert " .. tostring(pt.type))
   end
end

local function convert(pt)
   if pt.type=="rpl_expression" then
      return ast.exp{exp = convert_exp(pt.subs[1]), pos=pos, fin=fin}
   elseif pt.type=="rpl_statements" then
      return ast.block{stmts = map(convert_stmt, pt.subs), pos=pos, fin=fin}
   else
      error("Internal error: do not know how to convert " .. tostring(pt.type))
   end
end

ast.from_parse_tree = convert

return ast
