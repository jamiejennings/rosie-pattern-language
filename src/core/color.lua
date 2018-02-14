---- -*- Mode: Lua; -*-                                                                           
----
---- color-output.lua    Takes match output from Rosie in the form of a Lua table, and produces a
----                     string that uses ANSI color codes to highlight patterns in custom colors.
----
---- © Copyright IBM Corporation 2016, 2017.
---- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
---- AUTHORS: Jamie A. Jennings, Kevin Zander


local co = {}

-- How to produce useful color output

-- Each Rosie "match" of a pattern against some input data is internally represented as a parse
-- tree.  When a parse tree is encoded as a JSON document, you can see the tree structure in the
-- form of objects within other objects.  In other words, a match can have "sub-matches".

-- Because a match is a tree, it is not obvious how to choose a color when printing a match.  For
-- example, a match to the pattern 'net.ipv6' could be shown in red, like other network patterns,
-- or it could be shown as a series of underlined hex numbers (which are the sub-matches of
-- net.ipv6).  

-- Using the leaf nodes of the tree will obscure the "higher meaning" that the arrangement of
-- these nodes match a larger pattern, namely the one at the root node of the tree.  Alas, we
-- cannot provide in advance any default colors for user-defined patterns; nor can we expect users
-- to define a color for each of their patterns.  This suggests that we should allow matches to be
-- split when printed into segments of varying color.  So, when a user creates a pattern
-- containing a date and a network address as sub-matches, they can identify sub-matches easily by
-- color (assuming that patterns in the date and net packages are given default colors).

-- Depth-first tree coloring

-- Conceptually, we can use a depth-first traversal to color a tree in a way that produces the
-- variously colored segments we will print.  If the root of the tree (e.g. 'net.ip') has an
-- assigned color, then that is the color for this entire match.  In other words, we can stop the
-- descent into lower nodes.  And if the root of the tree, e.g. 'net.any' does not have an
-- assigned color, then we traverse the tree trying to find an assigned color for each node, and
-- descending no further in that subtree when we find one.

-- Default colors

-- Another consideration is how users can specify custom colors for library patterns or their own
-- patterns.  It would be convenient to specify a color for all patterns in a package,
-- e.g. 'net.*', instead of having to name them all.  Further, it would be nice to be able to have
-- a different color for some of those patterns, such as printing all 'net.*' patterns in red,
-- except for 'net.ipv6', which should print in orange.

-- Since Rosie's package system is simple (there are no nested packages), we can achieve this
-- easily.  If there is a color assigned to a pattern type (e.g. 'net.ipv6'), then the text
-- matching that pattern is printing using that color.  If not, then look for a package-level
-- wildcard pattern (e.g. 'net.*'), and use that color.  Finally, if there is no package-level
-- wildcard, then use the global wildcard color, '*'.

-- Combining depth-first coloring with wildcard colors

-- We must address the case in which there is a color for patterns defined by a wildcard, such as
-- 'net.*', but there are also colors assigned to specific patterns in the 'net' package
-- (e.g. 'net.ipv6').  We can modify our depth-first coloring algorithm to be aware of wildcard
-- colors.

-- Before we had wildcard colors, we would not visit the children of a node that we have colored.
-- But if a node's color was assigned not with an exact match to the node type, but instead by a
-- wildcard match, then we must visit the children in case any of them have a color assignment
-- that overrides the parent.  To keep things simple, we will define "C overrides P" to mean that
-- the color of the child C is assigned to C's node type precisely (with no wildcard) AND the
-- color of the parent P is assigned by wildcard match to P's node type.

-- A limitation

-- Despite the simplicity of Rosie's package system, it is flexible enough to allow you to import
-- a module under a different name from the one declared inside the module.  When you "import X as
-- Y", you get all the things in package X, e.g. a and b, but you refer to them as Y.a and Y.b
-- instead of the default X.a and X.b.

-- The color assignment system does not know how to map from the module names that are declared
-- inside module files and what you might map them to.  (This is something that is, in fact,
-- possible to do!  But it is not done today.)

-- As a result, if you have a color assignment for pattern X.a, but you "import X as Y", then your
-- output will include match types such as Y.a, which will not trigger the coloring unless you
-- also add entries for Y.a.

local list = require "list"
local violation = require "violation"
--local throw = violation.raise
--local catch = violation.catch
--local is_exception = violation.is_exception

local map = list.map; apply = list.apply; append = list.append;

---------------------------------------------------------------------------------------------------
-- Build and query the color database
---------------------------------------------------------------------------------------------------

co.colormap = {["*"] = "default;bold";		    -- global default
	       ["net.*"] = "red";
	       ["net.host"] = "red";		    -- show host, not its constituent parts
	       ["net.fqdn"] = "red";		    -- show fqdn, not its constituent parts
	       ["net.ipv6"] = "red;underline";
	       ["net.path"] = "green";
	       ["net.MAC"] = "underline;green";
	       ["num.*"] = "underline";
	       ["word.*"] = "yellow";
	       ["all.identifier"] = "cyan";
	       ["id.*"] = "bold;cyan";
	       ["os.path"] = "green";
	       ["date.*"] = "blue";
	       ["time.*"] = "1;34";		    -- bold and blue
	       ["ts.*"] = "underline;blue";
	    }

local function query(db, key, query_type)
   if query_type=="exact" then return db[key]; end
   if query_type=="default" then return db[key..".*"]; end
   if query_type=="global_default" then return db["*"] or ""; end
   error("Internal error: invalid query type: " .. tostring(query_type))
end

if not query(co.colormap, nil, "global_default") then
   common.warn("No default color specified (using 'default', i.e. ANSI SGR 39)")
   co.colormap["*"] = "default"
end

function co.query(pattern_type, db)
   if not db then db = co.colormap; end
   if pattern_type=="*" then pattern_type = ""; end
   local c = query(db, pattern_type, "exact")
   if c then return c, "exact"; end
   local match_pkg, match_name = common.split_id(pattern_type)
   if match_pkg then
      c = query(db, match_pkg, "default")
      if c then return c, "default"; end
   end
   return query(db, nil, "global_default"), "default"
end
   
---------------------------------------------------------------------------------------------------
-- Take color and text and generate the ANSI-color output
---------------------------------------------------------------------------------------------------

local ansi_color_table = 
   { -- fg colors
     ["black"] = "30";
     ["red"] = "31";
     ["green"] = "32";
     ["yellow"] = "33";
     ["blue"] = "34";
     ["magenta"] = "35";
     ["cyan"] = "36";
     ["white"] = "37";
     ["default"] = "39";
     ["underline"] = "4";
     -- font attributes
     ["reverse"] = "7";
     ["bold"] = "1";
     ["blink"] = "5";
     ["underline"] = "4";
     ["none"] = "0";
     -- bg colors
     ["bg_black"] = "40";
     ["bg_red"] = "41";
     ["bg_green"] = "42";
     ["bg_yellow"] = "43";
     ["bg_blue"] = "44";
     ["bg_magenta"] = "45";
     ["bg_cyan"] = "46";
     ["bg_white"] = "47";
     ["bg_default"] = "49";
  }

local function memoize(fn)
   local answers = {}
   return function(arg)
	     local memo = answers[arg]
	     if memo then return memo; end
	     memo = fn(arg)
	     answers[arg] = memo
	     return memo
	  end
end

local function to_ansi_code1(color_spec)
   local number = ansi_color_table[color_spec] or color_spec
   if number:match("%d+$") then
      return number
   else
      common.warn("ignoring invalid color/attribute: " .. tostring(color_spec))
      return ""
   end
end

local to_ansi_code = memoize(to_ansi_code1)

local function split_color_spec(color_spec)
   local specs = {}
   for elem in color_spec:gmatch("([^;]*);?") do
      if elem~="" then
	 table.insert(specs, elem)
      end
   end -- for
   return specs
end

local function color_spec_to_numbers1(color_spec)
   local specs = split_color_spec(color_spec)
   return map(to_ansi_code, specs)
end

local color_spec_to_numbers = memoize(color_spec_to_numbers1)

function co.color_string(color_spec, str)
   if not color_spec then return str; end	    -- in case default is nil/false
   local numbers = color_spec_to_numbers(color_spec)
   return "\027[" .. table.concat(numbers, ";") .. "m" .. str .. "\027[0m"
end

---------------------------------------------------------------------------------------------------
-- Walk the match structure (a parse tree) and generate the color output
---------------------------------------------------------------------------------------------------

local function color(match, db, pkgname, pkgcolor, global_default)
   local mtype = (match.type~="*") and match.type
   local c = query(db, mtype, "exact")
   -- Exact match in color database: print in color c
   if c then return list.new{c, match.s, match.e}; end
   local match_pkg, match_name = common.split_id(mtype or "")
   if not match_pkg then
      if not match.subs then
	 return list.new{global_default, match.s, match.e}
      else -- Defer to the subs.
	 return apply(append,
		      map(function(sub)
			     return color(sub, db, pkgname, pkgcolor, global_default)
			  end,
			  match.subs))
      end
   else -- There is a match_pkg
      if match_pkg ~= pkgname then
	 pkgcolor = query(db, match_pkg, "default")
	 if pkgcolor then pkgname = match_pkg; end
      end
      if match_pkg==pkgname then
	 if not match.subs then
	    return list.new{pkgcolor, match.s, match.e}
	 else
	    -- Defer to the subs.
	    return apply(append,
			 map(function(sub)
				return color(sub, db, pkgname, pkgcolor, global_default)
			     end,
			     match.subs))
	 end
      else 
	 if not match.subs then
	    return list.new{global_default, match.s, match.e}
	 else
	    -- Defer to the subs.
	    return apply(append,
			 map(function(sub)
				return color(sub, db, pkgname, pkgcolor, global_default)
			     end,
			     match.subs))
	 end -- if/else match.subs
      end -- if/else match_pkg==pkgname
   end -- if/else match_pkg
   assert(false, "could not find color")
end

local function map_apply(fn, list_of_arglists)
   return map(function(arglist)
		 return apply(fn, arglist)
	      end,
	      list_of_arglists)
end

local function db_from_colors1(colors)
   local entries = util.split(colors, ":")
   local db = {}
   for _, entry in ipairs(entries) do
      local key_value = util.split(entry, '=')
      -- Cases: empty entry; invalid entry; valid entry
      if key_value[1] and (key_value[1]~="") then
	 -- Entry is not empty
	 if (not key_value[2]) then
	    common.warn("ignoring invalid color assignment: ", entry)
	 else
	    db[key_value[1]] = key_value[2]
	 end
      end
   end -- for
   return db
end

local db_from_colors = memoize(db_from_colors1)

function co.match(match, input, colors)
   local db = (colors and db_from_colors(colors)) or co.colormap
   local global_default = query(db, nil, "global_default")
   if #input==0 then return ""; end
   local last = 0
   local function color_span(color_spec, s, e)
      local retval, msg, colorized
      if s > last+1 then
	 retval = input:sub(last+1, s-1)
      else
	 retval = ""
      end
      last = e-1
      colorized, msg = co.color_string(color_spec, input:sub(s, last))
      if not colorized then
	 common.note(msg)
	 return retval .. input:sub(s, last)
      else
	 return retval .. colorized
      end
   end
   local tbl = map_apply(color_span,
			 color(match, db, nil, nil, global_default))
   if last < #input then
      table.insert(tbl, input:sub(last+1))
   end
   return table.concat(tbl)
end

return co
