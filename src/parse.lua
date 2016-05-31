---- -*- Mode: Lua; -*-                                                                           
----
---- parse.lua   parse rosie pattern language
----
---- © Copyright IBM Corporation 2016.
---- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
---- AUTHOR: Jamie A. Jennings


local common = require "common"
require "utils"

local parse = {}

local lpeg = require "lpeg"
local P, V, C, S, R, Ct, Cg, Cp = lpeg.P, lpeg.V, lpeg.C, lpeg.S, lpeg.R, lpeg.Ct, lpeg.Cg, lpeg.Cp

local locale = lpeg.locale()

local function special_token(id, lpeg_pattern)
   return common.match_node_wrap(lpeg_pattern, id)
end

local function token_capture(id, lpeg_pattern)
   return common.match_node_wrap(C(lpeg_pattern), id)
end

local token = token_capture

----------------------------------------------------------------------------------------
-- Ignore whitespace and all comments
----------------------------------------------------------------------------------------
local ignore = (locale.space + (P"--" * ((P(1) - (P"\n"))^0)))^0


local id_char = locale.alnum + S"_"
local id = locale.alpha * id_char^0
local identifier = token_capture("identifier", (id * ("." * id)^0 * (- id_char)) + S".$")
local literal_string = special_token("string", (P'"' * (C(((1 - S'"\\') + (P'\\' * 1))^0)) * P'"'))
local top_level_syntax_error = token("syntax_error", Ct(Cg(ignore*(C(1)-locale.space)^1, "top_level")))

local star = token_capture("star", S"*");
local question = token_capture("question", S"?");
local plus = token_capture("plus", S"+");

----------------------------------------------------------------------------------------
-- Charset grammar
----------------------------------------------------------------------------------------
local character = token_capture("character", (P(1) - S"\\]") + (P"\\" * locale.print))   -- OR a numeric syntax???
local character_range = token("range", (character * P"-" * character * #P"]"));
local character_list = token("charlist", (character^1));
local character_set = P{"charset";
		  charset = (V"named" + V"plain" + V"charset_syntax_error");
		  named = special_token("named_charset", P"[:" * C((locale.print-(S":\\"))^1) * P":]");
		  plain = token("charset", P"["  * (V"contents"^-1) * P"]");
		  charset_syntax_error = token("syntax_error", Ct(Cg(Ct(P"[" * C((locale.print-P"]"))^1 * P"]"), "charset")));
		  contents = ( character_range
			       + character_list
			       + token_capture("syntax_error", Ct(Cg(Ct(P(1)-P"]"), "charset_contents")))
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

local quantifier = (star + question + plus + repetition)

local end_token = P"end" * #(locale.space + P(-1))

local alias_prefix = (P"alias" * ignore * identifier * ignore * P'=');
local assignment_prefix = (identifier * ignore * P'=');
local grammar_prefix = (P"grammar" * ignore * (alias_prefix + assignment_prefix));
local statement_prefix = ignore * (alias_prefix + grammar_prefix + end_token + assignment_prefix);

local expression = P{"expression";
	       expression = (V"statement_error" + V"ordered_choice" + V"sequence" + V"quantified_exp" + V"plain_exp");
	       statement_error = token("syntax_error", Ct(Cg(Ct(statement_prefix), "exp_stmt")));
	       ordered_choice = token("choice", ((V"quantified_exp" + V"plain_exp") * ignore * (P"/" * ignore * V"expression")));
	       -- sequences are tricky because we have to stop without consuming the next statement
	       sequence = token("sequence", ((V"quantified_exp" + V"plain_exp") * (ignore * (V"expression" - statement_prefix))^1));

	       plain_exp = (ignore * (identifier
				      + literal_string
				      + V"raw"
				      + V"cooked"
				      + character_set
				      + V"lookat"
				      + V"negation"));
	       quantified_exp = token("quantified_exp", (V"plain_exp" * ignore * quantifier));
	       cooked = token("cooked", P"(" * ignore * V"expression"^1 * ignore * P")");
	       raw = token("raw", P"{" * ignore * V"expression"^1 * ignore * P"}");
	       negation = token("negation", ignore * P"!" * (V"quantified_exp" + V"plain_exp"));
	       lookat = token("lookat", ignore * P"@" * (V"quantified_exp" + V"plain_exp"));
}

local statement = P{"start";
	      start = ignore * (V"alias" + V"grammar" + V"assignment");
	      alias = token("alias_", (alias_prefix * ignore * expression));
	      assignment = token("assignment_", (assignment_prefix * ignore * expression));
	      grammar = token("grammar_", P"grammar" * ignore * ((V"alias" + V"assignment") * ignore)^1 * end_token);
	      }

----------------------------------------------------------------------------------------
-- Top level
----------------------------------------------------------------------------------------

local any_token = (statement + expression + top_level_syntax_error) * Cp()

function parse.parse_without_error_check(str, pos, tokens)
   pos = pos or 1
   tokens = tokens or {}
   local nt, nextpos = any_token:match(str, pos)
   if (not nt) then return tokens; end
   table.insert(tokens, nt)
   return parse.parse_without_error_check(str, nextpos, tokens)
end

function parse.parse(str, pos, tokens)
   local astlist = parse.parse_without_error_check(str, pos, tokens)
   local errlist = {};
   for _,a in ipairs(astlist) do
      if parse.syntax_error_check(a) then table.insert(errlist, a); end
   end
   return astlist, errlist
end

----------------------------------------------------------------------------------------
-- Syntax error detection
----------------------------------------------------------------------------------------
-- return the clause that contains a syntax error, else nil
function parse.syntax_error_check(ast)
   local function found_one(a) return a; end;
   local function none_found(a) return nil; end;
   local function check_many_branches(a)
      local ans
      assert(a, "did not get ast in check_many_branches")
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
		      --group=check_many_branches;
		      raw=check_many_branches;
		      cooked=check_many_branches;
		      choice=check_two_branches;
		      identifier=none_found;
		      string=none_found;
		      character=none_found;
		      sequence=check_two_branches;
		      negation=check_one_branch;
		      lookat=check_one_branch;
		      named_charset=none_found;
		      charset=check_one_branch;
		      charlist=check_many_branches;
		      range=check_two_branches;
		      quantified_exp=check_two_branches;
		      plus=none_found;
		      question=none_found;
		      star=none_found;
		      repetition=none_found;
		      assignment_=check_two_branches;
		      alias_=check_two_branches;
		      grammar_=check_many_branches;
		      syntax_error=found_one;
		   }
   return common.walk_ast(ast, functions)
end

----------------------------------------------------------------------------------------
-- Reveal
----------------------------------------------------------------------------------------

local function reveal_identifier(a)
   assert(a, "did not get ast in reveal_identifier")
   local name, pos, text = common.decode_match(a)
   return text
end

local function reveal_assignment(a)
   assert(a, "did not get ast in reveal_assignment")
   local name, pos, text, subs = common.decode_match(a)
   assert(name=="assignment_")
   assert(next(subs[1])=="identifier")
   assert(type(subs[2])=="table")	    -- the right side of the assignment
   assert(not subs[3])
   local fmt = "assignment %s = %s"
   local id, e = subs[1], subs[2]
   return string.format(fmt,
			parse.reveal_exp(id),
			parse.reveal_exp(e))
end

local function reveal_grammar(a)
   assert(a, "did not get ast in reveal_grammar")
   local name, pos, text, subs = common.decode_match(a)
   assert(name=="grammar_")
   assert(type(subs[1])=="table")
   local str = "grammar\n"
   for i = 1, #subs do
      local rule = subs[i]
      assert(rule, "did not get rule in reveal_grammar")
      local rname, rpos, rtext = common.decode_match(rule)
      str = str .. "   " .. parse.reveal_ast(rule) .. "\n" 
   end
   str = str.. "end"
   return str
end

local function reveal_alias(a)
   assert(a, "did not get ast in reveal_alias")
   local name, pos, text, subs = common.decode_match(a)
   assert(name=="alias_")
   assert(next(subs[1])=="identifier")
   local fmt = "alias %s = %s"
   local id, e = subs[1], subs[2]
   return string.format(fmt,
			parse.reveal_exp(id),
			parse.reveal_exp(e))
end

local function reveal_binding(a)
   assert(a, "did not get ast in reveal_binding")
   local name, pos, text, subs = common.decode_match(a)
   assert(name=="binding")
   assert(next(subs[1])=="identifier")
   local fmt = "%s = %s"
   local id, e = subs[1], subs[2]
   return string.format(fmt,
			parse.reveal_exp(id),
			parse.reveal_exp(e))
end

local function reveal_sequence(a)
   assert(a, "did not get ast in reveal_sequence")
   local function rs(a)
      local name, pos, text, subs = common.decode_match(a)
      local e1, e2 = subs[1], subs[2]
      local str1, str2
      if next(e1)=="sequence" then str1 = rs(e1)
      else str1 = parse.reveal_exp(e1); end
      if next(e2)=="sequence" then str2 = rs(e2)
      else str2 = parse.reveal_exp(e2); end
      return str1 .. " " .. str2
   end
   return "< " .. rs(a) .. " >"
end

local function reveal_string(a)
   assert(a, "did not get ast in reveal_string")
   local name, pos, text = common.decode_match(a)
   return string.format('%q', text)
end

local function reveal_negation(a)
   assert(a, "did not get ast in reveal_negation")
   local name, pos, text, subs = common.decode_match(a)
   return "!"..parse.reveal_exp(subs[1])
end

local function reveal_lookat(a)
   assert(a, "did not get ast in reveal_lookat")
   local name, pos, text, subs = common.decode_match(a)
   return "@"..parse.reveal_exp(subs[1])
end

local function reveal_repetition(a)
   assert(a, "did not get ast in reveal_repetition")
   local name, pos, text, subs = common.decode_match(a)
   assert(subs[1], "did not get ast for min in reveal_repetition")
   local miname, minpos, mintext = common.decode_match(subs[1])
   assert(subs[2], "did not get ast for max in reveal_repetition")
   local maxname, maxpos, maxtext = common.decode_match(subs[2])
   return "{"..mintext..","..maxtext.."}"
end

local function reveal_quantified_exp(a)
   assert(a, "did not get ast in reveal_quantified_exp")
   local name, pos, text, subs = common.decode_match(a)
   local e, q = subs[1], subs[2]
   assert(q, "did not get quantifier exp in reveal_quantified_exp")
   local qname, qpos, printable_q = common.decode_match(q)
   assert(qname=="question" or qname=="star" or qname=="plus" or qname=="repetition")
   return "<" .. parse.reveal_exp(e) .. ">" .. (((qname=="repetition") and reveal_repetition(q)) or printable_q)
end

local function reveal_named_charset(a)
   assert(a, "did not get ast in reveal_named_charset")
   local name, pos, text = common.decode_match(a)
   return "[:".. text .. ":]"
end

local function reveal_charlist(a)
   assert(a, "did not get ast in reveal_charlist")
   local name, pos, text, subs = common.decode_match(a)
   assert(name=="charlist")
   local exps = "";
   for i = 1, #subs do
      assert(subs[i], "did not get a character ast in reveal_charlist")
      local cname, cpos, ctext = common.decode_match(subs[i])
      assert(cname=="character")
      exps = exps .. ctext
   end
   return exps
end

local function reveal_charset(a)
   assert(a, "did not get ast in reveal_charset")
   local name, pos, text, subs = common.decode_match(a)
   -- empty character lists are allowed
   if not(1) then return "[]"
   elseif next(subs[1])=="range" then
      local rname, rpos, rtext, rsubs = common.decode_match(subs[1])
      assert(rsubs[1], "did not get low sub in reveal_charset")
      assert(rsubs[2], "did not get high sub in reveal_charset")
      local lowname, lowpos, lowtext = common.decode_match(rsubs[1])
      local hiname, hipos, hitext = common.decode_match(rsubs[2])
      assert(lowname=="character")
      assert(hiname=="character")
      assert(not rsubs[3])
      return "[" ..  lowtext.. "-" .. hitext .. "]"
   elseif next(subs[1])=="charlist" then
      return "["..reveal_charlist(subs[1]).."]"
   else
      error("Reveal error: Unknown charset type: ".. next(subs[1]))
   end
end

local function reveal_choice(a)
   assert(a, "did not get ast in reveal_choice")
   local name, pos, text, subs = common.decode_match(a)
--   return "(" .. parse.reveal_exp(subs[1]) .. " / " .. parse.reveal_exp(subs[2]) .. ")";
   return parse.reveal_exp(subs[1]) .. " / " .. parse.reveal_exp(subs[2]);
end

local function reveal_capture(a)
   assert(a, "did not get ast in reveal_capture")
   local name, pos, text, subs = common.decode_match(a)
   return "CAP(" .. parse.reveal_exp(subs[1]) .. ")"
end

local function reveal_group(a)
   assert(a, "did not get ast in reveal_group")
   local name, pos, text, subs = common.decode_match(a)
   assert(name=="raw" or name=="cooked" or name=="raw_exp")
   local exps = nil
   for i = 1, #subs do
      local item = subs[i]
      if exps then exps = exps .. " " .. parse.reveal_exp(item)
      else exps = parse.reveal_exp(item)
      end
   end						    -- for each item in group
   if name=="cooked" then return "(" .. exps .. ")";
   else return "{" .. exps .. "}";
   end
end

function parse.reveal_syntax_error(a)
   -- name is "syntax_error"
   -- subs[1] is the type of syntax error, e.g. "exp_stmt" or "top_level"
   -- When the type is "exp_stmt", it has subs:
   --   subs[1] is the type of statement, e.g. "alias_", "assignment_"
   --   subs[2] is the expression the parser was looking at when the error happened
   -- When the type is "top_level", it has a sub:
   --   subs[1] is the offending string
   assert(a, "did not get ast in reveal_syntax_error")
   local name, pos, text, subs = common.decode_match(a)
   if text=="top_level" then
      return "SYNTAX ERROR (TOP LEVEL): " .. tostring(subs[1])
   elseif text=="exp_stmt" then
      if next(subs[2])=="assignment_" then
	 return "SYNTAX ERROR: ASSIGNMENT TO " .. parse.reveal_ast(subs[3])
      elseif next(subs[2])=="alias_" then
	 return "SYNTAX ERROR: ALIAS " .. parse.reveal_ast(subs[3])
      else
	 return "SYNTAX ERROR: (UNKNOWN STATEMENT TYPE) " .. parse.reveal_ast(subs[3])
      end
   elseif text=="charset" then
      return "SYNTAX ERROR: CHARSET " .. tostring(subs[1]) .. " ..."
   else
      return "SYNTAX ERROR: " .. text
   end
end

parse.reveal_exp = function(a)
   local functions = {"reveal_exp";
		      capture=reveal_capture;
		      group=reveal_group;
		      raw=reveal_group;
		      raw_exp=reveal_group;
		      cooked=reveal_group;
		      choice=reveal_choice;
		      sequence=reveal_sequence;
		      negation=reveal_negation;
		      lookat=reveal_lookat;
		      identifier = reveal_identifier;
		      string=reveal_string;
		      named_charset=reveal_named_charset;
		      charset=reveal_charset;
		      quantified_exp=reveal_quantified_exp;
		      cooked_quantified_exp=reveal_quantified_exp; -- !@#
		      syntax_error=parse.reveal_syntax_error;
		   }
   return common.walk_ast(a, functions);
end

function parse.reveal_ast(ast)
   assert(type(ast)=="table", "Reveal: first argument not an ast: "..tostring(ast))
   assert(type(next(ast))=="string", "Reveal: first argument not an ast: "..tostring(ast))
   local functions = {"reveal_ast";
		      binding=reveal_binding;
		      assignment_=reveal_assignment;
		      alias_=reveal_alias;
		      grammar_=reveal_grammar;
		      exp=parse.reveal_exp;
		      default=parse.reveal_exp;
		   }
   return common.walk_ast(ast, functions);
end
   
function parse.reveal(astlist)
   assert(type(astlist)=="table", "Reveal: first argument not an ast: "..tostring(astlist))
   assert(type(astlist[1])=="table", "Reveal: first argument not list of ast's: "..tostring(astlist))
   local s;
   for _,ast in ipairs(astlist) do
      if s then s = s .. "\n" .. parse.reveal_ast(ast)
      else s = parse.reveal_ast(ast)
      end
   end
   return s
end

-- For parsing the Rosie core:
function parse.core_parse_and_explain(source)
   assert(type(source)=="string", "Compiler: source argument is not a string: "..tostring(source))
   local astlist, errlist = parse.parse(source)
   if #errlist~=0 then
      local msg = "Core parser reports syntax errors:\n"
      for _,e in ipairs(errlist) do
	 msg = msg .. "\n" .. compile.explain_syntax_error(e, source)
      end
      return false, msg
   else -- successful parse
      return astlist
   end
end

return parse
