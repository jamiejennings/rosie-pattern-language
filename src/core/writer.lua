---- -*- Mode: Lua; -*-                                                                           
----
---- writer.lua   ast->string functions
----
---- © Copyright IBM Corporation 2016, 2017.
---- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
---- AUTHOR: Jamie A. Jennings


local string = require "string"
local common = require "common"
local list = require "list"

local writer = {}

----------------------------------------------------------------------------------------
-- Reveal
----------------------------------------------------------------------------------------

local function reveal_identifier(a)
   assert(a, "did not get ast in reveal_identifier")
   local name, pos, text = common.decode_match(a)
   return text
end

local function reveal_ref(a)
   assert(a, "did not get ast in reveal_ref")
   local name, pos, text = common.decode_match(a)
   if name=="ref" then return text
   else error("Unknown ref type in reveal_ref: " .. tostring(name))
   end
end

local function reveal_assignment(a)
   assert(a, "did not get ast in reveal_assignment")
   local name, pos, text, subs = common.decode_match(a)
   assert(name=="assignment_")
   assert(subs[1].type=="identifier")
   assert(type(subs[2])=="table")	    -- the right side of the assignment
   assert(not subs[3])
   local fmt = "assignment %s = %s"
   local id, e = subs[1], subs[2]
   return string.format(fmt,
			writer.reveal_exp(id),
			writer.reveal_exp(e))
end

local function reveal_grammar(a)
   assert(a, "did not get ast in reveal_grammar")
   local name, pos, text, subs = common.decode_match(a)
   assert(name=="grammar_" or name=="new_grammar")
   assert(type(subs[1])=="table")
   local str = name .."\n"
   for i = 1, #subs do
      local rule = subs[i]
      assert(rule, "did not get rule in reveal_grammar")
      local rname, rpos, rtext = common.decode_match(rule)
      str = str .. "   " .. writer.reveal_ast(rule) .. "\n" 
   end
   str = str.. "end"
   return str
end

local function reveal_alias(a)
   assert(a, "did not get ast in reveal_alias")
   local name, pos, text, subs = common.decode_match(a)
   assert(name=="alias_")
   assert(subs[1].type=="identifier")
   local fmt = "alias %s = %s"
   local id, e = subs[1], subs[2]
   return string.format(fmt,
			writer.reveal_exp(id),
			writer.reveal_exp(e))
end

local function reveal_binding(a)
   assert(a, "did not get ast in reveal_binding")
   local name, pos, text, subs = common.decode_match(a)
   assert(name=="binding")
   assert(subs[1].type=="identifier")
   local fmt = "%s = %s"
   local id, e = subs[1], subs[2]
   return string.format(fmt,
			writer.reveal_exp(id),
			writer.reveal_exp(e))
end

local function reveal_sequence(a)
   assert(a, "did not get ast in reveal_sequence")
   local function rs(a)
      local name, pos, text, subs = common.decode_match(a)
      local e1, e2 = subs[1], subs[2]
      local str1, str2
      if e1.type=="sequence" then str1 = rs(e1)
      else str1 = writer.reveal_exp(e1); end
      if e2.type=="sequence" then str2 = rs(e2)
      else str2 = writer.reveal_exp(e2); end
      return str1 .. " " .. str2
   end
   return "(" .. rs(a) .. ")"
end

local function reveal_string(a)
   assert(a, "did not get ast in reveal_string")
   local name, pos, text = common.decode_match(a)
   return string.format('%q', text)
end

local function reveal_predicate(a)
   assert(a, "did not get ast in reveal_predicate")
   local name, pos, text, subs = common.decode_match(a)
   local pred_type = subs[1].type
   local exp = subs[2]
   return subs[1].text .. writer.reveal_exp(subs[2])
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
   local open, close = "(", ")"
   if e.type=="raw_exp" then
      return writer.reveal_exp(e) .. (((qname=="repetition") and reveal_repetition(q)) or printable_q)
   else
      return open .. writer.reveal_exp(e) .. close .. (((qname=="repetition") and reveal_repetition(q)) or printable_q)
   end
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
      exps = exps .. ctext
   end
   return "[" .. exps .. "]"
end

local function reveal_range(a)
   assert(a, "did not get ast in reveal_range")
   local name, pos, text, subs = common.decode_match(a)
   assert(name=="range")
   assert(subs and subs[1])
   local complement = (subs[1].type=="complement")
   local offset = 0
   if complement then
      assert(subs[2] and subs[3])
      offset = 1
   end
   local lowname, lowpos, lowtext = common.decode_match(subs[1+offset])
   local hiname, hipos, hitext = common.decode_match(subs[2+offset])
   assert(lowname=="character")
   assert(hiname=="character")
   assert(not subs[3+offset])
   return "[" ..  ((complement and "^") or "") .. lowtext.. "-" .. hitext .. "]"
end

local function reveal_charset(a)
   assert(a, "did not get ast in reveal_charset")
   local name, pos, text, subs = common.decode_match(a)
   if subs[1].type=="range" then
      return reveal_range(subs[1])
   elseif subs[1].type=="charlist" then
      return reveal_charlist(subs[1])
   else
      error("Reveal error: Unknown charset type: ".. subs[1].type)
   end
end

local function reveal_charset_exp(a)
   assert(a, "did not get ast in reveal_charset_exp")
   local name, pos, text, subs = common.decode_match(a)
   assert(subs and subs[1])
   local complement = (subs[1].type=="complement")
   local offset = 0
   if complement then
      assert(subs[2])
      offset = 1
   end
   local retval = ""
   for i=1+offset,#subs do
      local sub = subs[i]
      local name = sub.type
      if name=="range" then retval = retval .. reveal_range(sub)
      elseif name=="charlist" then retval = retval .. reveal_charlist(sub)
      elseif name=="named_charset" then retval = retval .. reveal_named_charset(sub)
      else error("Reveal error: Unknown charset expression type: ".. name)
      end
   end -- for
   return "[" .. ((complement and "^") or "") .. retval .. "]"
end

-- return a list of choices
local function flatten_choice(ast)
   local name = ast.type
   if name=="choice" then
      return list.apply(list.append, list.map(syntax.flatten_choice, list.from(ast.subs)))
   else
      return {ast}
   end
end

local function reveal_choice(a)
   assert(a, "did not get ast in reveal_choice")
   local name, pos, text, subs = common.decode_match(a)
   local choices = flatten_choice(a)
   local msg = ""
   local n = #choices
   for i=1, n do
      msg = msg .. writer.reveal_exp(choices[i])
      if i<n then msg = msg .. " / "; end
   end
   return msg
end

local function reveal_capture(a)
   assert(a, "did not get ast in reveal_capture")
   local name, pos, text, subs = common.decode_match(a)
   return "CAPTURE as " .. writer.reveal_exp(subs[1]) .. ": " .. writer.reveal_exp(subs[2])
end

local function reveal_group(a)
   assert(a, "did not get ast in reveal_group")
   local name, pos, text, subs = common.decode_match(a)
   assert(name=="raw" or name=="cooked" or name=="raw_exp")
   local exps = nil
   for i = 1, #subs do
      local item = subs[i]
      if exps then exps = exps .. " " .. writer.reveal_exp(item)
      else exps = writer.reveal_exp(item)
      end
   end						    -- for each item in group
   if name=="cooked" then return "(" .. exps .. ")";
   else return "{" .. exps .. "}";
   end
end

---------------------------------------------------------------------------------------------------
-- Exported interface
---------------------------------------------------------------------------------------------------

function writer.reveal_syntax_error(a)
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
      if subs[2].type=="assignment_" then
	 return "SYNTAX ERROR: ASSIGNMENT TO " .. writer.reveal_ast(subs[3])
      elseif subs[2].type=="alias_" then
	 return "SYNTAX ERROR: ALIAS " .. writer.reveal_ast(subs[3])
      else
	 return "SYNTAX ERROR: (UNKNOWN STATEMENT TYPE) " .. writer.reveal_ast(subs[3])
      end
   elseif text=="charset" then
      return "SYNTAX ERROR: CHARSET " .. tostring(subs[1]) .. " ..."
   else
      return "SYNTAX ERROR: " .. text
   end
end

writer.reveal_exp = function(a)
   local functions = {"reveal_exp";
		      capture=reveal_capture;
		      ref=reveal_ref;
		      predicate=reveal_predicate;
		      group=reveal_group;
		      raw=reveal_group;
		      raw_exp=reveal_group;
		      cooked=reveal_group;
		      choice=reveal_choice;
		      sequence=reveal_sequence;
		      identifier = reveal_identifier;
		      literal=reveal_string;
		      named_charset=reveal_named_charset;
		      charset=reveal_charset;
		      charset_exp=reveal_charset_exp;
		      charlist=reveal_charlist;
		      range=reveal_range;
		      quantified_exp=reveal_quantified_exp;
		      new_quantified_exp=reveal_quantified_exp;
		      cooked_quantified_exp=reveal_quantified_exp;
		      raw_quantified_exp=reveal_quantified_exp;
		      syntax_error=writer.reveal_syntax_error;
		   }
   return common.walk_ast(a, functions);
end

function writer.reveal_ast(ast)
   assert(type(ast)=="table", "Reveal: first argument not an ast: "..tostring(ast))
   assert(type(ast.type)=="string", "Reveal: first argument not an ast: "..tostring(ast))
   local functions = {"reveal_ast";
		      binding=reveal_binding;
		      assignment_=reveal_assignment;
		      alias_=reveal_alias;
		      grammar_=reveal_grammar;
		      new_grammar=reveal_grammar;
		      exp=writer.reveal_exp;
		      default=writer.reveal_exp;
		   }
   return common.walk_ast(ast, functions);
end
   
function writer.reveal(astlist)
   assert(type(astlist)=="table", "Reveal: first argument not an ast: "..tostring(astlist))
   assert(type(astlist[1])=="table", "Reveal: first argument not list of ast's: "..tostring(astlist))
   local s;
   for _,ast in ipairs(astlist) do
      if s then s = s .. "\n" .. writer.reveal_ast(ast)
      else s = writer.reveal_ast(ast)
      end
   end
   return s
end

return writer
