-- -*- Mode: Lua; -*-                                                                             
--
-- rpl-parser.lua
--
-- © Copyright IBM Corporation 2016, 2017.
-- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
-- AUTHOR: Jamie A. Jennings

local decode_match = common.decode_match

----------------------------------------------------------------------------------------
-- Driver functions for RPL parser written in RPL
----------------------------------------------------------------------------------------

local function rosie_parse_without_error_check(rplx, str, pos, tokens)
   pos = pos or 1
   local results = {}
   local tokens, leftover = rplx:match(str, pos)
   local name, pos, text, subs = decode_match(tokens)
   return subs or {}, leftover
end

local function rosie_parse(rplx, str, pos, tokens)
   local astlist, leftover = rosie_parse_without_error_check(rplx, str, pos, tokens)
   local errlist = {};
   for _,a in ipairs(astlist) do
      if parse.syntax_error_check(a) then table.insert(errlist, a); end
   end
   return astlist, errlist, leftover
end

function preparse(rplx_preparse, input)
   local major, minor
   local language_decl, leftover
   if type(input)=="string" then
      language_decl, leftover = rplx_preparse:match(input)
   elseif type(input)=="table" then
      -- assume astlist
      if input[1].type=="language_decl" then
	 language_decl = input[1]
	 leftover = #input - language_decl.fin
      end
   else
      error("preparse called with neither string nor astlist as input: " .. tostring(input))
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

function make_preparser(rplx_preparse, supported_version)
   local incompatible = function(major, minor, supported)
			   return (major > supported.major) or (major==supported.major and minor > supported.minor)
			end
   return function(source)
	     local major, minor, pos = preparse(rplx_preparse, source)
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

function make_parse_and_explain(preparse, supported_version, rplx_rpl, syntax_expand)
   return function(source)
	     local maj, min, pos, err
	     assert(type(source)=="string",
		    "Error: source argument is not a string: "..tostring(source) ..
		    "\n" .. debug.traceback())
	     if preparse then
		-- preparse to look for rpl language version declaration
		maj, min, pos, err = preparse(source, supported_version)
		if not maj then return nil, nil, err; end
	     else
		pos = 1
	     end
	     -- input is compatible with what is supported, so continue parsing
	     local original_astlist, errlist, leftover = rosie_parse(rplx_rpl, source, pos)
	     local astlist = syntax_expand(original_astlist)
	     -- if syntax errors, then generate readable explanations
	     if #errlist~=0 then
		local msgs = {}
		table.insert(msgs, "Warning: syntax error reporting is limited at this time")
		for _,e in ipairs(errlist) do
		   table.insert(msgs, parse.explain_syntax_error(e, source))
		end
		return nil, nil, msgs, leftover
	     else
		-- successful parse
		return astlist, original_astlist, {}, leftover
	     end
	  end -- parse and explain function
end -- make_parse_and_explain

-- parse_deps takes input (source or astlist) and returns a table of dependencies calculated by
-- processing any import statements.  the table contains entries with the keys: 
-- importpath, prefix, env.
-- Notes:
-- (1) env is assigned during compilation, to hold the module environment
-- (2) prefix is filled in here iff there is an "as" clause in the import statment,
--     else it will be filled in later with the package name from the module source
function parse_deps(parser, input)
   local maj, min, pos, err = parser.preparse(input)
   if not maj then return nil, err; end
   local astlist, orig_astlist, messages
   if type(input)=="string" then
      astlist, orig_astlist, messages = parser.parse_statements(input)
      if not astlist then return nil, messages; end
   elseif type(input)=="table" then
      astlist, orig_astlist = input, input
   else
      error("argument not a string or astlist: " .. tostring(input))
   end
   local i = 1
   if not astlist[i] then return nil, {"empty list of statements"}; end
   local typ, pos, text, specs, fin = decode_match(astlist[i])
   assert(typ~="language_decl", "language declaration should be handled in preparse/parse")
   if typ=="package_decl" then
      -- skip the package decl, if any
      i=i+1;
      typ, pos, text, specs, fin = decode_match(astlist[i])
   end
   local deps = {}
   local importpath, prefix
   while typ=="import_decl" do
      for _,spec in ipairs(specs) do
	 local typ, pos, text, subs, fin = decode_match(spec)
	 assert(subs and subs[1], "missing package name to import?")
	 local typ, pos, importpath = decode_match(subs[1])
	 importpath = common.dequote(importpath)
	 common.note("*\t", "import |", importpath, "|")
	 if subs[2] then
	    typ, pos, prefix = decode_match(subs[2])
	    assert(typ=="packagename" or typ=="dot")
	    common.note("\t  as ", prefix)
--	 else
--	    _, prefix = util.split_path(importpath, "/")
	 end
	 table.insert(deps, {importpath=importpath, prefix=prefix})
      end -- for each importspec in the import_decl
      i=i+1;
      if not astlist[i] then break; end
      typ, pos, text, specs, fin = common.decode_match(astlist[i])
   end
   return deps
end
   

