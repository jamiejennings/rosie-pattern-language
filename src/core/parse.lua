---- -*- Mode: Lua; -*-                                                                           
----
---- parse.lua   parse rosie pattern language: rpl 0.0
----
---- © Copyright IBM Corporation 2016, 2017.
---- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
---- AUTHOR: Jamie A. Jennings


local string = require "string"
local table = require "table"
local common = require "common"
local rmatch = common.rmatch

local util = require "util"

local parse = {}

local lpeg = require "lpeg"
local P, V, C, S, R = lpeg.P, lpeg.V, lpeg.C, lpeg.S, lpeg.R
local rC = lpeg.rcap

local locale = lpeg.locale()

local function token_capture(id, lpeg_pattern)
   return common.match_node_wrap(lpeg_pattern, id)
end

local token = token_capture

----------------------------------------------------------------------------------------
-- Ignore whitespace and all comments
----------------------------------------------------------------------------------------
local ignore = (locale.space + (P"--" * ((P(1) - (P"\n"))^0)))^0


local id_char = locale.alnum + S"_"
local id = locale.alpha * id_char^0
local identifier = token("identifier", (id * ("." * id)^0 * (- id_char)) + S".$")
local literal_string = token("literal0", P'"' * (((1 - S'"\\') + (P'\\' * 1))^0) * P'"')
local top_level_syntax_error = token("syntax_error", rC(ignore*(C(1)-locale.space)^1, "top_level"))

local star = token("star", S"*");
local question = token("question", S"?");
local plus = token("plus", S"+");

----------------------------------------------------------------------------------------
-- Charset grammar
----------------------------------------------------------------------------------------
local character = token("character", (P(1) - S"\\]") + (P"\\" * locale.print))   -- OR a numeric syntax???
local character_range = token("range", (character * P"-" * character * #P"]"));
local character_list = token("charlist", (character^1));
local character_set = P{"charset";
		  charset = (V"named" + V"plain" + V"charset_syntax_error");
		  named = token("named_charset0", P"[:" * ((locale.print-(S":\\"))^1) * P":]");
		  plain = token("charset", P"["  * (V"contents"^-1) * P"]");
		  charset_syntax_error = token("syntax_error", (P"[" * rC((locale.print-P"]")^1, "charset") * P"]"));
		  contents = ( character_range
			       + character_list
			       + token("syntax_error", rC(P(1)-P"]", "charset_contents"))
			 );
	       }
----------------------------------------------------------------------------------------
-- Repetition grammar with curly braces
----------------------------------------------------------------------------------------
local integer = locale.digit^0
local repetition = token("repetition", 
			 P"{"
			    * ignore * token("low",integer)
			    * ignore * "," * ignore *
			    token("high",integer) * ignore * P"}");
-- Matches {n,m}, {n,} and {,m} where n, m are integers, but not {} or {,}

----------------------------------------------------------------------------------------
-- Statements and Expressions
----------------------------------------------------------------------------------------

local negation = token("negation", P"!")
local lookat = token("lookat", P"@")
local predicate_symbol = negation + lookat

local quantifier = (star + question + plus + repetition)

local end_token = P"end" * #(locale.space + P(-1))

local alias_prefix = (P"alias" * ignore * identifier * ignore * P'=');
local assignment_prefix = (identifier * ignore * P'=');
local grammar_prefix = (P"grammar" * ignore * (alias_prefix + assignment_prefix));
local statement_prefix = ignore * (alias_prefix + grammar_prefix + end_token + assignment_prefix);

local expression = P{"expression";
	       expression = (V"statement_error" + V"ordered_choice" + V"sequence" + V"quantified_exp" + V"plain_exp");
	       statement_error = token("syntax_error", rC(statement_prefix, "exp_stmt"));
	       ordered_choice = token("choice", ((V"quantified_exp" + V"plain_exp") * ignore * (P"/" * ignore * V"expression")));
	       -- sequences are tricky because we have to stop without consuming the next statement
	       sequence = token("sequence", ((V"quantified_exp" + V"plain_exp") * (ignore * (V"expression" - statement_prefix))^1));

	       plain_exp = (ignore * (identifier
				      + literal_string
				      + V"raw"
				      + V"cooked"
				      + (P"[" * character_set * P"]")
				   + V"predicate"
			     ));
	       quantified_exp = token("quantified_exp", (V"plain_exp" * ignore * quantifier));
	       cooked = token("cooked", P"(" * ignore * V"expression"^1 * ignore * P")");
	       raw = token("raw", P"{" * ignore * V"expression"^1 * ignore * P"}");
	       predicate = token("predicate", ignore * predicate_symbol * (V"quantified_exp" + V"plain_exp"));
	    }

local statement = P{"start";
	      start = ignore * (V"alias" + V"grammar" + V"assignment");
	      alias = token("alias_", (alias_prefix * ignore * expression));
	      assignment = token("assignment_", (assignment_prefix * ignore * expression));
	      grammar = token("grammar_", P"grammar" * ignore * ((V"alias" + V"assignment") * ignore)^1 * end_token);
	      }

-- here we fake-parse a package declaration, which is not part of the core language
-- so that we can put such a declaration into rpl_1_0.rpl, which is parsed by core.
local fake_package = token("fake_package",
			   ignore * P"package" * locale.space^1 * (P(1) - P"=") * ((P(1) - (P"\n"))^0))

----------------------------------------------------------------------------------------
-- Top level
----------------------------------------------------------------------------------------

local any_token = (fake_package + statement + expression + top_level_syntax_error)

function parse_without_error_check(str, pos, tokens)
   pos = pos or 1
   tokens = tokens or {}
   local nt, nextpos = rmatch(any_token, str, pos)
   if (not nt) then return tokens, #str-pos+1; end  -- return ASTlist and leftover
   table.insert(tokens, nt)
   return parse_without_error_check(str, nextpos, tokens)
end

----------------------------------------------------------------------------------------
-- Syntax error detection
----------------------------------------------------------------------------------------
-- return the clause that contains a syntax error, else nil
function parse.syntax_error_check(ast)
   local function found_one(a) return a; end;
   local function none_found(a) return nil; end;
   local function check_all_branches(a)
      local ans
      assert(a, "did not get ast in check_all_branches")
      local name, pos, text, subs = common.decode_match(a)
      if subs then
	 for i = 1, #subs do
	    ans = parse.syntax_error_check(subs[i])
	    if ans then return ans; end
	 end -- for each
      end -- if subs
      return nil
   end
   local function check_two_branches(a)
      assert(a, "did not get ast in check_two_branches")
      local name, pos, text, subs = common.decode_match(a)
      return parse.syntax_error_check(subs[1]) or parse.syntax_error_check(subs[2])
   end
   local function check_one_branch(a)
      assert(a, "did not get ast in check_one_branch")
      local name, pos, text, subs = common.decode_match(a)
      return parse.syntax_error_check(subs[1])
   end
   local functions = {"syntax_error_check";
		      raw=check_all_branches;
		      cooked=check_all_branches;
		      choice=check_two_branches;
		      identifier=none_found;
		      literal0=none_found;
		      character=none_found;
		      sequence=check_two_branches;
		      predicate=check_two_branches;
		      negation=none_found;
		      lookat=none_found;
		      named_charset=none_found;
		      charset_exp=check_all_branches;
		      charset=check_one_branch;	    -- USED ONLY IN CORE
		      charlist=check_all_branches;
		      range=check_two_branches;
		      complement=none_found;
		      quantified_exp=check_two_branches;
		      plus=none_found;
		      question=none_found;
		      star=none_found;
		      repetition=none_found;
		      assignment_=check_two_branches;
		      alias_=check_two_branches;
		      grammar_=check_all_branches;
		      syntax_error=found_one;
		      default=check_all_branches;   -- Monday, March 6, 2017
		   }
   return common.walk_ast(ast, functions)
end

----------------------------------------------------------------------------------------
-- Parser for the Rosie core language, i.e. rpl 0.0
----------------------------------------------------------------------------------------

function parse.core_parse(source)
   assert(type(source)=="string", "Core parser: source argument is not a string: "..tostring(source))
   local astlist, leftover = parse_without_error_check(source)
   assert(type(leftover)=="number")
   local errlist = {};
   for _,a in ipairs(astlist) do
      if parse.syntax_error_check(a) then table.insert(errlist, a); end
   end
   if #errlist==0 then
      return common.create_match("core", 1, source, table.unpack(astlist)),
             {},				    -- 2nd return value is empty table of messages
	     leftover
   else
      assert(false, "Core parser reports syntax errors:\n" ..
	     util.table_to_pretty_string(errlist) .. "\n")
   end
end

function parse.core_parse_expression(source)
   local ast, errs, leftover = parse.core_parse(source)
   if not ast then return nil, errs, leftover; end
   assert(type(ast)=="table" and ast.type=="core")
   if not (ast.subs and ast.subs[1]) then return nil, "empty expression", #source
   elseif ast.subs and ast.subs[2] then return nil, "not an expression", #source
   else return ast, errs, leftover; end
end
      
return parse
