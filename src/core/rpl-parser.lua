-- -*- Mode: Lua; -*-                                                                             
--
-- rpl-parser.lua
--
-- © Copyright IBM Corporation 2016, 2017.
-- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
-- AUTHOR: Jamie A. Jennings

local common = require "common"
local decode_match = common.decode_match
local util = require "util"
local parse = require "parse"

----------------------------------------------------------------------------------------
-- Driver functions for RPL parser written in RPL
----------------------------------------------------------------------------------------

local rpl_parser = {}

----------------------------------------------------------------------------------------
-- Syntax error reporting (default capability)
----------------------------------------------------------------------------------------

local function explain_syntax_error(a, source)
   local err = parse.syntax_error_check(a)
   assert(err)
   local name, pos, text, subs = common.decode_match(a)
   local line, pos, lnum = util.extract_source_line_from_pos(source, pos)

   local msg = string.format("Syntax error at line %d: %s\n", lnum, text) .. string.format("%s\n", line)

   msg = msg .. "While looking for " .. name .. "\n"

   local ename, errpos, etext, esubs = common.decode_match(err)
   msg = msg .. (string.rep(" ", errpos-1).."^".."\n")

   if esubs then
      -- We only examine the first sub for now, assuming there are no others.  A better syntax
      -- error reporting technique is needed.
      local etname, etpos, ettext, etsubs = common.decode_match(esubs[1])
      if etname=="statement_prefix" then
	 msg = msg .. "Found start of a new statement inside an expression.\n"
      else
	 msg = msg .. "No additional information is available.\n"
      end
   end -- if esubs
   return msg
end

local function rosie_parse(rplx, str, pos, tokens)
   local ast, leftover = rplx:match(str, pos)
   local errlist = {};
   for _,a in ipairs(ast.subs or {}) do
      if parse.syntax_error_check(a) then table.insert(errlist, a); end
   end
   return ast, errlist, leftover
end

function rpl_parser.preparse(rplx_preparse, input)
   local major, minor
   local language_decl, leftover
   if type(input)=="string" then
      language_decl, leftover = rplx_preparse:match(input)
   elseif type(input)=="table" then
      -- assume ast provided, although it will be empty even if the original source was not, 
      -- because the source could contain only comments and/or whitespace
      if not input[1] then return nil, nil, 1; end
      if input[1].type=="language_decl" then
	 language_decl = input[1]
	 leftover = #input - language_decl.fin
      end
   else
      assert(false, "preparse called with neither string nor ast as input: " .. tostring(input))
   end
   if language_decl then
      if parse.syntax_error_check(language_decl) then
	 return false, "Syntax error in language version declaration: " .. language_decl.text
      else
	 major = tonumber(language_decl.subs[1].subs[1].text) -- major
	 minor = tonumber(language_decl.subs[1].subs[2].text) -- minor
	 return major, minor, #input-leftover+1
      end
   else
      return nil, nil, 1
   end
end


local function vstr(maj, min)
   return tostring(maj) .. "." .. tostring(min)
end

function rpl_parser.make_preparser(rplx_preparse, supported_version)
   local incompatible = function(major, minor, supported)
			   return (major > supported.major) or (major==supported.major and minor > supported.minor)
			end
   return function(source)
	     local major, minor, pos = rpl_parser.preparse(rplx_preparse, source)
	     if major then
		common.note("-> Parser noted rpl version declaration ", vstr(major, minor))		
		if incompatible(major, minor, supported_version) then
		   return nil, nil, nil,
		   "Error: loading rpl that requires version " .. vstr(major, minor) ..
		   " but engine is at version " .. vstr(supported_version.major, supported_version.minor)
	        end
		if major < supported_version.major then
		   common.warn("loading rpl source at version " ..
			vstr(major, minor) .. 
		     " into engine at version " ..
		     vstr(supported_version.major, supported_version.minor))
		end
		return major, minor, pos
	     else
		common.note("-> Parser saw no rpl version declaration")
		return 0, 0, 1
	     end -- if major
	  end -- preparser function
end -- make_preparser

function rpl_parser.make_parse_and_explain(preparse, supported_version, rplx_rpl, syntax_expand)
   return function(source, origin, msgs)
	     local maj, min, pos, err
	     assert(type(msgs)=="table")
	     assert(type(source)=="string",
		    "Error: source argument is not a string: "..tostring(source) ..
		    "\n" .. debug.traceback())
	     if preparse then
		-- preparse to look for rpl language version declaration
		maj, min, pos, err = preparse(source, supported_version)
		if not maj then
		   table.insert(msgs, err)
		   return nil, nil, pos; end
	     else
		pos = 1
	     end
	     -- input is compatible with what is supported, so continue parsing
	     local original_ast, errlist, leftover = rosie_parse(rplx_rpl, source, pos)
	     local ast = syntax_expand(original_ast)
	     -- if syntax errors, then generate readable explanations
	     if #errlist~=0 then
		--table.insert(msgs, "Warning: syntax error reporting is limited at this time")
		for _,e in ipairs(errlist) do
		   table.insert(msgs, explain_syntax_error(e, source))
		end
		return nil, nil, leftover
	     else
		-- successful parse
		return ast, original_ast, leftover
	     end
	  end -- parse and explain function
end -- make_parse_and_explain

-- expand_import_decl takes a single import decl parse node and expands it into a list of as many
-- individual import declarations as it contains.  The individual declarations are added to the
-- results table (i.e. that argument is side-effected).
function rpl_parser.expand_import_decl(decl_parse_node, results)
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
end

-- parse_deps takes input (source or ast) and returns a table of dependencies calculated by
-- processing any import statements.  the table contains entries with the keys: 
-- importpath, prefix, env.
-- Notes:
-- (1) env is assigned during compilation, to hold the module environment
-- (2) prefix is filled in here iff there is an "as" clause in the import statment,
--     else it will be filled in later with the package name from the module source
function rpl_parser.parse_deps(parser, input)
   local maj, min, pos, err = parser.preparse(input)
   if not maj then return nil, err; end
   local message = {}
   local ast, orig_ast
   if type(input)=="string" then
      ast, orig_ast, leftover = parser.parse_statements(input, nil, messages)
      if not ast then return nil, messages; end
   elseif type(input)=="table" then
      ast, orig_ast = input, input
   else
      error("argument not a string or ast: " .. tostring(input))
   end
   local astlist = ast.subs or {}
   local i = 1
   if not astlist[i] then return nil, {"empty list of statements"}; end
   local typ, pos, text, specs, fin = decode_match(astlist[i])
   assert(typ~="language_decl", "language declaration should be handled in preparse/parse")
   if typ=="package_decl" then
      -- skip the package decl, if any
      i=i+1;
   end
   local deps = {}
   while astlist[i] and astlist[i].type=="import_decl" do
      rpl_parser.expand_import_decl(astlist[i], deps)
      i=i+1;
   end
   return deps
end
   

return rpl_parser
