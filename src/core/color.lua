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
local throw = violation.throw
local catch = violation.catch

local map = list.map; apply = list.apply; append = list.append;

---------------------------------------------------------------------------------------------------
-- Build and query the color database
---------------------------------------------------------------------------------------------------

co.colormap = {["*"] = "black";			    -- global default
	       ["net.*"] = "red";
	       --["net.fqdn"] = "magenta";
	       ["net.ipv6"] = "red;underline";

	       ["num.*"] = "underline";

	       ["word.*"] = "yellow";
	       ["word.id"] = "cyan";
	       ["word.id1"] = "cyan";
	       ["word.id2"] = "cyan";
	       ["word.id3"] = "cyan";
	       ["word.dotted_id"] = "cyan";

	       ["os.path"] = "green";

	       ["date.any"] = "blue";
	       ["time.time"] = "4;34";		    -- underline & blue
	    }

local function query(db, key, query_type)
   if query_type=="exact" then return db[key]; end
   if query_type=="default" then return db[key..".*"]; end
   if query_type=="global_default" then return db["*"]; end
   error("Internal error: invalid query type: " .. tostring(query_type))
end

if not query(co.colormap, nil, "global_default") then
   common.warn("No default color specified")
   co.colormap["*"] = "default"
end

function co.query(pattern_type, db)
   if not db then db = co.colormap; end
   if pattern_type=="*" then pattern_type = ""; end
   local c = query(db, pattern_type, "exact")
   if c then return c, "exact"; end
   local match_pkg, match_name = common.split_identifier(pattern_type)
   if match_pkg then
      c = query(db, pattern_type, "default")
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

local function to_ansi_code(color_spec)
   local number = ansi_color_table[color_spec] or color_spec
   if number:match("%d+$") then
      return number
   else
      throw("invalid color specification: " .. tostring(color_spec))
   end
end

local function split_color_spec(color_spec)
   local specs = {}
   for elem in color_spec:gmatch("([^;]*);?") do
      if elem~="" then
	 table.insert(specs, elem)
      end
   end -- for
   return specs
end

function co.color_string(color_spec, str)
   local specs = split_color_spec(color_spec)
   local ok, numbers, bad_spec_msg = catch(map, to_ansi_code, specs)
   if not ok then error(numbers); end
   if not numbers then return false, bad_spec_msg; end
   return "\027[" .. table.concat(numbers, ";") .. "m" .. str .. "\027[0m"
end

---------------------------------------------------------------------------------------------------
-- Walk the match structure (a parse tree) and generate the color output
---------------------------------------------------------------------------------------------------

local function color(match, db, pkgname, pkgcolor, global_default)
   local mtype = (match.type~="*") and match.type
   local c = query(db, mtype, "exact")
   -- Exact match in color database: print in color c
   if c then return list.new{c, match.data}; end
   -- Else, if match is a leaf, then check for a default color
   local match_pkg, match_name = common.split_identifier(mtype or "")
   if not match.subs then
      if match_pkg then
	 if not pkgname then
	    -- We were not given any default package with a default color, so
	    -- look for one.
	    pkgcolor = query(db, match_pkg, "default")
	    if pkgcolor then
	       return list.new{pkgcolor, match.data}
	    else
	       return list.new{global_default, match.data}
	    end
	 elseif (match_pkg==pkgname) then
	    return list.new{pkgcolor, match.data}
	 end
      else
	 -- The match does not have a pkg prefix (only a local name, match_name).  And we know
	 -- also that there is no assigned color for this exact match type.
	 return list.new{global_default, match.data}
      end
   else
      -- Else, there are sub-matches.  Print each sub-match in its own color.  Start by looking
      -- for a package default, provided we were not given one already.
      if (not pkgname) and match_pkg then
	 pkgcolor = query(db, match_pkg, "default")
	 if pkgcolor then pkgname = match_pkg; end
      end
      return apply(append, map(function(sub)
				  return color(sub, db, pkgname, pkgcolor, global_default)
			       end,
			       match.subs))
   end
end

local function map_apply(fn, list_of_arglists)
   return map(function(arglist)
		 return apply(fn, arglist)
	      end,
	      list_of_arglists)
end

function co.match(match, db)
   if not db then db = co.colormap; end
   local global_default = query(db, nil, "global_default")
   assert(global_default, "no global default color value?")
   return table.concat(map_apply(co.color_string, color(match, db, nil, nil, global_default)),
		       " ")
end



-- Rewrite notes
--
-- (1) Write node_to_color_text
--
-- To convert a node to text using a colormap, do this:
--   If the colormap is empty:
--     Return the text field of the node
--   ElseIf the node name has a color entry in the colormap:
--     Return the color encoding string .. text field of the node .. color reset string
--   Else, return concatenation of the node-to-text of each child of node (breadth first)
--
-- (2) Change the color encoding to use the rgb approach instead (TEST it first!)
--
-- (3) Move the color encoding functions to a common place, like utils

-- local common = require "common"

-- local function csi(rest)
--    return "\027[" .. rest
-- end

-- -- Colors

-- local shell_color_table = 
--    { -- fg colors
--      ["black"] = csi("30m");
--      ["red"] = csi("31m");
--      ["green"] = csi("32m");
--      ["yellow"] = csi("33m");
--      ["blue"] = csi("34m");
--      ["magenta"] = csi("35m");
--      ["cyan"] = csi("36m");
--      ["white"] = csi("37m");
--      ["default"] = csi("39m");
--      ["underline"] = csi("4m");
--      -- font attributes
--      ["reverse"] = csi("7m");
--      ["bold"] = csi("1m");
--      ["blink"] = csi("5m");
--      ["underline"] = csi("4m");
--      ["none"] = csi("0m");
--      -- bg colors
--      ["bg_black"] = csi("40m");
--      ["bg_red"] = csi("41m");
--      ["bg_green"] = csi("42m");
--      ["bg_yellow"] = csi("43m");
--      ["bg_blue"] = csi("44m");
--      ["bg_magenta"] = csi("45m");
--      ["bg_cyan"] = csi("46m");
--      ["bg_white"] = csi("47m");
--      ["bg_default"] = csi("49m");
--   }


-- co.old_colormap = {["."] = "black";
-- 	    ["basic.unmatched"] = "black";
-- 	    ["simplified_json"] = "yellow";	    -- won't work. need aliases within grammars.
-- 	    ["word.any"] = "yellow";

--             ["net.any"] = "red";
--             ["net.fqdn"] = "yellow";
--             ["net.url"] = "red";
--             ["http_command"] = "red";
--             ["http_version"] = "red";
--             ["net.ip"] = "red";
--             ["net.ipv4"] = "red";
--             ["net.ipv6"] = "magenta";
--             ["net.email"] = "red";

-- 	    -- ["num.any"] = "underline";
-- 	    -- ["num.int"] = "underline";
-- 	    -- ["num.float"] = "underline";
-- 	    -- ["num.mantissa"] = "underline";
-- 	    -- ["num.exponent"] = "underline";
-- 	    -- ["num.hex"] = "underline";
-- 	    -- ["num.denoted_hex"] = "underline";

-- 	    ["word.id"] = "cyan";
-- 	    ["word.id1"] = "cyan";
-- 	    ["word.id2"] = "cyan";
-- 	    ["word.id3"] = "cyan";
-- 	    ["word.dotted_id"] = "cyan";

-- 	    ["os.path"] = "green";

-- 	    ["basic.datetime_patterns"] = "blue";
-- 	    ["basic.network_patterns"] = "red";
       
--             ["datetime.datetime_RFC3339"] = "blue";
--             ["datetime.slash_datetime"] = "blue";
--             ["datetime.simple_slash_date"] = "blue";
--             ["datetime.shortdate"] = "blue";
--             ["datetime.ordinary_date"] = "blue";
--             ["datetime.simple_date"] = "blue";
--             ["datetime.simple_datetime"] = "blue";
--             ["datetime.full_date_RFC3339"] = "blue";
--             ["datetime.date_RFC2822"] = "blue";
--             ["datetime.time_RFC2822"] = "blue";
--             ["datetime.full_time_RFC3339"] = "blue";
--             ["datetime.simple_time"] = "blue";
--             ["datetime.funny_time"] = "blue";
       
-- 	 }


-- local already_warned = {}

-- function co.color(key)
--    local c = co.old_colormap[key]
--    if not c then
--       if VERBOSE and not already_warned[key] then
-- 	 io.stderr:write("Warning: No color defined in color map for object of type: '",
-- 			 tostring(key),
-- 			 "'\n");
-- 	 already_warned[key] = true;
--       end
--       c = "black";
--    end
--    return c, shell_color_table[c]
-- end

-- local reset_color_attributes = shell_color_table["none"]

-- function co.color_print_leaf_nodes(t)
--    -- t is a match
--    local name, pos, text, subs = common.decode_match(t)
--    if (not subs) or (#subs==0) then
--       -- already at a leaf node
--       local cname, ccode = co.color(name)
--       text = tostring(text);			    -- just in case!
--       io.write(ccode, text, reset_color_attributes, " ");
--    else
--       for i = 1, #subs do
-- 	 co.color_print_leaf_nodes(subs[i]);
--       end -- for all sub-matches
--    end
-- end

-- function co.color_write(channel, color, ...)
--    channel:write(shell_color_table[color])
--    for _,v in ipairs({...}) do
--       channel:write(v)
--    end
--    channel:write(reset_color_attributes)
-- end

-- function co.color_string_from_leaf_nodes(t)
--    -- t is a match
--    if not t then return ""; end
--    local output = ""
--    local name, pos, text, subs = common.decode_match(t)
--    if (not subs) or (#subs==0) then
--       -- already at a leaf node
--       local cname, ccode = co.color(name)
--       text = tostring(text);			    -- just in case!
--       return ccode .. text .. reset_color_attributes .. " ";
--    else
--       for i = 1, #subs do
-- 	 output = output .. co.color_string_from_leaf_nodes(subs[i]);
--       end -- for all sub-matches
--       return output
--    end
-- end

-- function co.string_from_leaf_nodes(t)
--    -- t is a match
--    if not t then return ""; end
--    local output = ""
--    local name, pos, text, subs = common.decode_match(t)
--    if (not subs) or (#subs==0) then
--       -- already at a leaf node
--       return tostring(text) .. " "		    -- tostring is just in case!
--    else
--       for i = 1, #subs do
-- 	 output = output .. co.string_from_leaf_nodes(subs[i]);
--       end -- for all sub-matches
--       return output
--    end
-- end

return co
