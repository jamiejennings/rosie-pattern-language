-- -*- Mode: Lua; -*-                                                                             
--
-- ast.lua    ast crud for Rosie Pattern Language
--
-- © Copyright IBM Corporation 2017.
-- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
-- AUTHOR: Jamie A. Jennings

-- TODO: Save the source along with the ast (it already has start/end)


local recordtype = require "recordtype"
local NIL = recordtype.NIL
local list = require "list"
map = list.map; apply = list.apply; append = list.append;
local rpl_parser = require "rpl-parser"

local ast = {}

ast.block = recordtype.new("block",
			   {stmts = {};
			    importpath = NIL;	    -- origin of this block from import stmt
			                            -- or nil for top level
			    filename = NIL;	    -- origin of this block from file system
			                            -- or nil, e.g. for user input in CLI or REPL
			    pdecl = NIL;	    -- filled in during expansion
			    ideclist = NIL;	    -- filled in during expansion
			    s = NIL;
			    e = NIL;})

ast.binding = recordtype.new("binding",
			  {ref = NIL;
			   exp = NIL;
			   is_alias = false;
			   is_local = false;
			   s = NIL;
			   e = NIL;})

-- A grammar is an expression in the ast, despite the fact that in the concrete grammar for rpl
-- 1.1, the keyword 'grammar' introduces a binding of a name to a 'grammar expression'.
ast.grammar = recordtype.new("grammar",
			     {rules = {};
			      s = NIL;
			      e = NIL;})

ast.ref = recordtype.new("ref",
			 {localname = NIL;
			  packagename = NIL;
			  s = NIL;
			  e = NIL;})

ast.sequence = recordtype.new("sequence",
			 {exps = {};
			  s = NIL;
			  e = NIL;})

ast.choice = recordtype.new("choice",
			    {exps = {};
			     s = NIL;
			     e = NIL;})

ast.predicate = recordtype.new("predicate",
			  {type = NIL;
			   exp = NIL;
			   s = NIL;
			   e = NIL;})

ast.repetition = recordtype.new("repetition",
			 {min = NIL;
			  max = NIL;
			  exp = NIL;
			  cooked = false;
			  s = NIL;
			  e = NIL;})

ast.cooked = recordtype.new("cooked",
			  {exp = NIL;
			   s = NIL;
			   e = NIL;})

ast.raw = recordtype.new("raw",
			 {exp = NIL;
			  s = NIL;
			  e = NIL;})


ast.literal = recordtype.new("literal",			    -- interpolated string literals
			     {value = NIL;		    -- raw value, as seen in rpl source
			      s = NIL;
			      e = NIL;})

ast.cs_exp = recordtype.new("cs_exp",		    -- [ [exp1] ... ]
			  {complement = false;
			   cexp = {};
			   s = NIL;
			   e = NIL;})

ast.cs_named = recordtype.new("cs_named",	    -- [:name:]
			      {complement = false;
			       name = NIL;
			       s = NIL;
			       e = NIL;})

ast.cs_list = recordtype.new("cs_list",		    -- [abc12$]
			      {complement = false;
			       chars = {};
			       s = NIL;
			       e = NIL;})

ast.cs_range = recordtype.new("cs_range",	    -- [a-z]
			      {complement = false;
			       first = NIL;
			       last = NIL;
			       s = NIL;
			       e = NIL;})

ast.cs_union = recordtype.new("cs_union",	    -- [ [exp1] ... ]
				{cexps = {};
				 s = NIL;
				 e = NIL;})

ast.cs_intersection = recordtype.new("cs_intersection", -- [ [exp1]&&[exp2]&& ... ]
				       {cexps = {};
					s = NIL;
					e = NIL;})

ast.cs_difference = recordtype.new("cs_difference",	-- [ [first]-[second] ]
				     {first = NIL;
				      second = NIL;
				      s = NIL;
				      e = NIL;})

ast.application = recordtype.new("application",
				 {ref = NIL;
--				  kind = NIL;		    -- macro or function
--				  fn = NIL;		    -- actual macro/function to apply
				  raw = false;	    -- is arglist raw {} or cooked ()
				  arglist = NIL;
				  s = NIL;
				  e = NIL;})

ast.arglist = recordtype.new("arglist",
			     {cooked = true;
			      args = {};
			      s = NIL;
			      e = NIL;})

ast.int = recordtype.new("int",
			 {value = NIL;
			  s = NIL;
			  e = NIL;})

ast.pdecl = recordtype.new("pdecl",
			   {name = NIL;
			    s = NIL;
			    e = NIL;})

ast.idecl = recordtype.new("idecl",
			   {importpath = NIL;
			    prefix = NIL;
			    s = NIL;
			    e = NIL;})

ast.ideclist = recordtype.new("ideclist",
			      {idecls = {};
			       s = NIL;
			       e = NIL;})
			    
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
--      print("*** lifting: "); for i,v in ipairs(exps) do io.write(tostring(v), " "); end; io.write("\n")
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

local function convert_quantified_exp(pt)
   local s, e = pt.s, pt.e
   local exp, q = pt.subs[1], pt.subs[2]
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
   return ast.repetition.new{min = min,
			     max = max,
			     exp = convert_exp(exp),
			     s=s, e=e}
end

local convert_char_exp;

local function infix_to_prefix(exps)
   -- exps := exp (op exp)*
   local rest = list.from(exps)
   local first = rest[1]
   local op = rest[2]
   if not op then return convert_char_exp(first); end
   local optype = op.subs[1].type
   assert(optype)
   rest = list.cdr(list.cdr(rest))
   if optype=="intersection" then
      return ast.cs_intersection.new{cexps = {convert_char_exp(first), infix_to_prefix(rest)}, s=s, e=e}
   elseif optype=="difference" then
      return ast.cs_difference.new{first = convert_char_exp(first), second = infix_to_prefix(rest), s=s, e=e}
   elseif optype=="union" then
      return ast.cs_union.new{cexps = {convert_char_exp(first), infix_to_prefix(rest)}, s=s, e=e}
   else
      error("Internal error: do not know how to convert charset op " .. tostring(optype))
   end
end

function convert_char_exp(pt)
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
   local s, e = pt.s, pt.e
   if pt.type=="named_charset" then
      return ast.cs_named.new{name = exps[1].text, complement = compflag, s=s, e=e}
   elseif pt.type=="charlist" then
      return ast.cs_list.new{chars = map(function(sub) return sub.text; end, exps),
			     complement = compflag,
			     s=s, e=e}
   elseif pt.type=="range" then
      return ast.cs_range.new{first = exps[1].text,
			      last = exps[2].text,
			      complement = compflag,
			      s=s, e=e}
   elseif pt.type=="compound_charset" then
      assert(exps[1])
      local prefix_cexp = infix_to_prefix(exps)
      flatten_cexp_in_place(prefix_cexp, ast.cs_intersection)
      flatten_cexp_in_place(prefix_cexp, ast.cs_union)
      return ast.cs_exp.new{cexp = prefix_cexp,
			    complement = compflag,
			    s=s, e=e}
   else
      error("Internal error: do not know how to convert charset exp type: " .. tostring(pt.type))
   end
end

local function convert_identifier(pt)
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
   return ast.ref.new{localname=localname, packagename=packagename, s=s, e=e}
end   

function convert_exp(pt)
   local s, e = pt.s, pt.e
   if pt.type=="capture" then
      return ast.cap.new{name = pt.subs[1].text, exp = convert_exp(pt.subs[2]), s=s, e=e}
   elseif pt.type=="predicate" then
      return ast.predicate.new{type = pt.subs[1].text, exp = convert_exp(pt.subs[2]), s=s, e=e}
   elseif pt.type=="cooked" then
      return ast.cooked.new{exp = convert_exp(pt.subs[1]), s=s, e=e}
   elseif pt.type=="raw" then
      return ast.raw.new{exp = convert_exp(pt.subs[1]), s=s, e=e}
   elseif pt.type=="choice" then
      return ast.choice.new{exps = map(convert_exp, flatten(pt, "choice")), s=s, e=e}
   elseif pt.type=="sequence" then
      return ast.sequence.new{exps = map(convert_exp, flatten(pt, "sequence")), s=s, e=e}
   elseif pt.type=="identifier" then
      return convert_identifier(pt)
   elseif pt.type=="literal" then
      return ast.literal.new{value = pt.text, s=s, e=e}
   elseif pt.type=="charset_exp" then
      return convert_char_exp(pt)
   elseif pt.type=="quantified_exp" then
      return convert_quantified_exp(pt)
--   elseif pt.type=="arg" then
--      return convert_exp(pt.subs[1])
   elseif pt.type=="application" then
      local id = pt.subs[1]
      assert(id.type=="identifier")
      local operands
      local arglist = pt.subs[2]
      if (arglist.type=="arglist") then
	 -- Wrap non-numeric args in 'cooked'.
	 operands = map(function(arg)
			   if arg.type=="int" then
			      return arg
			   else
			      return ast.cooked.new{exp=convert_exp(arg),
						    s=arg.s, e=arg.e}
			   end
			end,
			arglist.subs)
      elseif (arglist.type=="rawarglist") then
	 -- Wrap non-numeric args in 'raw'.
	 operands = map(function(arg)
			   if arg.type=="int" then
			      return arg
			   else
			      return ast.raw.new{exp=convert_exp(arg),
						 s=arg.s, e=arg.e}
			   end
			end,
			arglist.subs)
      elseif (arglist.type=="arg") then
	 operands = list.new(convert_exp(arglist.subs[1]))
      else
	 error("Internal error: invalid arglist in application of " .. tostring(refname) ..
	       ": " .. tostring(arglist.type))
      end
      return ast.application.new{ref=convert_identifier(id),
			         arglist=operands,
			         s=s, e=e}
   else
      error("Internal error: do not know how to convert " .. tostring(pt.type))
   end
end

local function convert_stmt(pt)
   local s, e = pt.s, pt.e
   if pt.type=="assignment_" then
      assert(pt.subs and pt.subs[1] and pt.subs[2])
      return ast.binding.new{ref = convert_exp(pt.subs[1]),
			  exp = convert_exp(pt.subs[2]),
			  is_alias = false,
			  is_local = false,
			  s=s, e=e}
   elseif pt.type=="alias_" then
      return ast.binding.new{ref = convert_exp(pt.subs[1]),
			  exp = convert_exp(pt.subs[2]),
			  is_alias = true,
			  is_local = false,
			  s=s, e=e}
   elseif pt.type=="grammar_" then
      local rules = map(convert_stmt, pt.subs)
      assert(rules and rules[1])
      local aliasflag = rules[1].is_alias
      local boundref = rules[1].ref
      local gexp = ast.grammar.new{rules = rules,
				   s=s, e=e}
      return ast.binding.new{ref = boundref,
			  exp = gexp,
			  is_alias = aliasflag,
			  is_local = false}
   elseif pt.type=="local_" then
      local b = convert_stmt(pt.subs[1])
      b.is_local = true
      return b
   elseif pt.type=="package_decl" then
      assert(pt.subs and pt.subs[1])
      local pname = pt.subs[1].text
      return ast.pdecl.new{name=pname, s=s, e=e}
   elseif pt.type=="import_decl" then
      local deps = {}
      rpl_parser.expand_import_decl(pt, deps)
      local function to_idecl(dep)
	 return ast.idecl.new{importpath = dep.importpath,
			      prefix = dep.prefix}
      end
      return ast.ideclist.new{idecls = map(to_idecl, deps), s=s, e=e}
   else
      error("Internal error: do not know how to convert " .. tostring(pt.type))
   end
end

local function convert(pt)
   local s, e = pt.s, pt.e
   if pt.type=="rpl_expression" then
      assert(pt.subs and pt.subs[1] and (not pt.subs[2]))
      return convert_exp(pt.subs[1])
   elseif pt.type=="rpl_statements" then
      return ast.block.new{stmts = map(convert_stmt, pt.subs or {}), s=s, e=e}
   else
      error("Internal error: do not know how to convert " .. tostring(pt.type))
   end
end

ast.from_parse_tree = convert

---------------------------------------------------------------------------------------------------
-- Reconstruct valid RPL from an ast
---------------------------------------------------------------------------------------------------

function ast.tostring(a)
   if ast.block.is(a) then
      return ( (a.pdecl and (ast.tostring(a.pdecl) .. "\n") or "") ..
	       (a.ideclist and ast.tostring(a.ideclist) or "") ..
	       "RAW: " ..
	       table.concat(map(ast.tostring, a.stmts), "\nRAW: ") )
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
      return ( "grammar\n\t" ..
	       table.concat(map(ast.tostring, a.rules), "\t\n") ..
	       "end" )
   elseif ast.ref.is(a) then
      return ( (a.packagename and (a.packagename .. ".") or "") .. a.localname )
   elseif ast.sequence.is(a) then
      return "{" .. table.concat(map(ast.tostring, a.exps), " ") .. "}"
   elseif ast.choice.is(a) then
      local choices = map(ast.tostring, a.exps)
      assert(#choices > 0, "empty choice ast?")
      return "{" .. table.concat(choices, " / ") .. "}"
   elseif ast.predicate.is(a) then
      return a.type .. ast.tostring(a.exp)
   elseif ast.repetition.is(a) then
--      local open = a.cooked and "(" or "{"
--      local close = a.cooked and ")" or "}"
      local postfix
      if (not a.max) then
	 if a.min==0 then postfix = "*"
	 elseif a.min==1 then postfix = "+"
	 else postfix = "{" .. tostring(a.max) .. ",}"
	 end
      elseif a.min==0 then postfix = "?"
      else
	 postfix = "{" .. tostring(a.min) .. "," .. tostring(a.max) .. "}"
      end
--      if not ast.sequence.is(a.exp) then
--	 open, close = "", ""
--      end
--      return open .. ast.tostring(a.exp) .. close .. postfix
      return ast.tostring(a.exp) .. postfix
   elseif ast.cooked.is(a) then
      return "(" .. ast.tostring(a.exp) .. ")"
   elseif ast.raw.is(a) then
      return "{" .. ast.tostring(a.exp) .. "}"
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
      return ast.tostring(a.ref) .. ":" .. ast_tostring(arglist)
   else
      error("do not know how to print this ast: " .. tostring(a))
   end
end


return ast
