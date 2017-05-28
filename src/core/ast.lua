-- -*- Mode: Lua; -*-                                                                             
--
-- ast.lua    ast crud for Rosie Pattern Language
--
-- © Copyright IBM Corporation 2017.
-- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
-- AUTHOR: Jamie A. Jennings

local recordtype = require "recordtype"
local NIL = recordtype.NIL

local ast = {}

ast.exp = recordtype.new("exp",
			 {exp = NIL;
			  pos = NIL;
			  fin = NIL;})

ast.stmts = recordtype.new("stmts",
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


ast.lit = recordtype.new("lit",
			 {type = NIL;
			  value = NIL;
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


return ast


   

