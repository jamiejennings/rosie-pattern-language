-- -*- Mode: Lua; -*-                                                               
--
-- rcfile.lua
--
-- © Copyright Jamie A. Jennings 2018.
-- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
-- AUTHOR: Jamie A. Jennings

-- Here's the approach to reading initialization settings from ~/.rosierc:
--
-- The format is defined in an RPL module, and leverages elements of the RPL
-- parser.  We provide a function which will parse the contents of an rc file
-- (also called an init file), returning an array of elements.  Some elements
-- will be atmosphere (whitespace, comments) and some will be initialization
-- options.
--
-- Some initialization options may be repeated, and in that case, all the values
-- will be used, in the order seen.  We provide convenience functions here for
-- aggregating values from multiple instances of the same element (e.g. multiple
-- 'libpath' options).
--
-- The Rosie CLI, or any client of librosie, can decide where to find rcfile
-- contents.  Once obtained, the rcfile contents can be parsed and aggregated
-- using the functions below.  It is then up to the CLI or client program to
-- decide which, if any, of the initialization options to process.
--
-- Following unix tradition, the CLI will look for the file ~/.rosierc as the
-- "run command" or init file, and it will process all the options found there
-- before those found on the command line.  See the CLI documentation for
-- details. 
--
-- OPTIONS
--
-- libpath = “<filenames>”
-- colors = ”<colorspecs>" 
-- loadfile = “<filename>”
--
-- WHERE
--
-- <filenames> is one or more filenames in a colon-separated list.  An initial
--    "~/" will be expanded to "$HOME/".
--
-- <colorspecs> is one or more <colorspec> in a colon-separated list.
--
-- <colorspec> is <name>=<colors> where <colors> is one or more <color> in a
--    semi-colon-separated list.
--
-- <name> is an RPL identifier (unqualified) where the localname can be "*".
-- 
-- <color> is a small integer corresponding to an ANSI color or attribute, or a
--    Rosie-defined name for one of those, including "default"
--
-- The ANSI codes for font colors and attributes are called SGR parameters:
-- https://en.wikipedia.org/wiki/ANSI_escape_code#SGR_(Select_Graphic_Rendition)_parameters

rcfile = {}

import "list"
filter = list.filter

test = [[
      -- comment
      libpath = "foo"
      libpath = "bar:baz"  -- line comment
      file = "~/file-to-load.rpl"
      colors = "word.any=green;bold:num.*=red"
      colors = "num.int=red;bold;underline"
      file = "another-file"
      file = "a-third-file"
      other="some other key that could be anything"
      -- final comment
]]

-- rcfile.parse() parses the rcfile contents and returns the raw parse.
function rcfile.parse(input)
   local e = rosie.engine.new("rcfile parser")
   local ok, _, errs = e:import("rosie/rcfile")
   assert(ok)
   local p = e:compile("rcfile.options")
   assert(p)
   local m, leftover, abend = p:match(input)
   if not m then
      return nil, "error parsing rcfile input: parse failed"
   elseif (leftover ~= 0) then
      return nil, "error parsing rcfile input: leftover = " .. tostring(leftover)
   elseif abend then
      return nil, "error parsing rcfile input: match was aborted"
   end
   return m
end

-- rcfile.to_options() walks the parsetree elements, ignoring the atmosphere and
-- producing a key/value pair list of the options found.
function rcfile.to_options(parsetree)
   if not type(parsetree)=="table" then
      return nil, "process called with arg that is not a table: " .. tostring(parsetree)
   elseif parsetree.type~="rcfile.options" then
      return nil, "root of parse tree is not rcfile.options"
   end
   local subs = parsetree.subs
   local options = {}
   if not subs then return options; end
   for _, item in ipairs(subs) do
      if item.type=="rcfile.option" then
	 assert(item.subs[1] and item.subs[1].type=="rpl.localname")
	 local name = item.subs[1].data
	 assert(item.subs[2] and item.subs[2].type:sub(1,4)=="rpl.")
	 local value = item.subs[2].data
	 table.insert(options, {[name] = value})
      end
   end -- for
   return options
end

local function concat_with_colons(option_array, keyname)
   local values = {}
   for i, entry in ipairs(option_array) do
      local k,v = next(entry)
      if k==keyname then
	 table.insert(values, v)
      end
   end -- for
   if #values == 0 then return nil; end
   return table.concat(values, ":")
end

local function remove(option_array, keyname)
   return filter(function(entry) return (next(entry))~=keyname; end,
		 option_array)
end

-- rcfile.coalesce() produces a new option array.  For the set of recognized
-- keys, if a key is present multiple times and it can be coalesced, then the
-- new option array will have a single entry for that key, with a single
-- coalesced value.
function rcfile.coalesce(option_array)
   local libpath = concat_with_colons(option_array, "libpath")
   local colors = concat_with_colons(option_array, "colors")
   local new = remove(remove(option_array, "libpath"), "colors")
   table.insert(new, {libpath = libpath})
   table.insert(new, {colors = colors})
   return new
end

function rcfile.process(input)
   local parsetree, err = rcfile.parse(input)
   if not parsetree then return nil, err; end
   local options, err = rcfile.to_options(parsetree)
   if not options then return nil, err; end
   return rcfile.coalesce(options)
end

return rcfile
