---- -*- Mode: Lua; -*-                                                                           
----
---- color-output.lua    Takes match output from Rosie in the form of a Lua table, and produces a
----                     string that uses ANSI color codes to highlight patterns in custom colors.
----
---- © Copyright IBM Corporation 2016, 2017.
---- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
---- AUTHOR: Jamie A. Jennings


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

-- One last twist

-- Despite the simplicity of Rosie's package system, ...





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

local common = require "common"

local function csi(rest)
   return "\027[" .. rest
end

-- Colors

local shell_color_table = 
   { -- fg colors
     ["black"] = csi("30m");
     ["red"] = csi("31m");
     ["green"] = csi("32m");
     ["yellow"] = csi("33m");
     ["blue"] = csi("34m");
     ["magenta"] = csi("35m");
     ["cyan"] = csi("36m");
     ["white"] = csi("37m");
     ["default"] = csi("39m");
     ["underline"] = csi("4m");
     -- font attributes
     ["reverse"] = csi("7m");
     ["bold"] = csi("1m");
     ["blink"] = csi("5m");
     ["underline"] = csi("4m");
     ["none"] = csi("0m");
     -- bg colors
     ["bg_black"] = csi("40m");
     ["bg_red"] = csi("41m");
     ["bg_green"] = csi("42m");
     ["bg_yellow"] = csi("43m");
     ["bg_blue"] = csi("44m");
     ["bg_magenta"] = csi("45m");
     ["bg_cyan"] = csi("46m");
     ["bg_white"] = csi("47m");
     ["bg_default"] = csi("49m");
  }


co.colormap = {["."] = "black";
	    ["basic.unmatched"] = "black";
	    ["simplified_json"] = "yellow";	    -- won't work. need aliases within grammars.
	    ["word.any"] = "yellow";

            ["net.any"] = "red";
            ["net.fqdn"] = "red";
            ["net.url"] = "red";
            ["http_command"] = "red";
            ["http_version"] = "red";
            ["net.ip"] = "red";
            ["net.ipv4"] = "red";
            ["net.ipv6"] = "red";
            ["net.email"] = "red";

	    ["num.any"] = "underline";
	    ["num.int"] = "underline";
	    ["num.float"] = "underline";
	    ["num.mantissa"] = "underline";
	    ["num.exponent"] = "underline";
	    ["num.hex"] = "underline";
	    ["num.denoted_hex"] = "underline";

	    ["word.id"] = "cyan";
	    ["word.id1"] = "cyan";
	    ["word.id2"] = "cyan";
	    ["word.id3"] = "cyan";
	    ["word.dotted_id"] = "cyan";

	    ["os.path"] = "green";

	    ["basic.datetime_patterns"] = "blue";
	    ["basic.network_patterns"] = "red";
       
            ["datetime.datetime_RFC3339"] = "blue";
            ["datetime.slash_datetime"] = "blue";
            ["datetime.simple_slash_date"] = "blue";
            ["datetime.shortdate"] = "blue";
            ["datetime.ordinary_date"] = "blue";
            ["datetime.simple_date"] = "blue";
            ["datetime.simple_datetime"] = "blue";
            ["datetime.full_date_RFC3339"] = "blue";
            ["datetime.date_RFC2822"] = "blue";
            ["datetime.time_RFC2822"] = "blue";
            ["datetime.full_time_RFC3339"] = "blue";
            ["datetime.simple_time"] = "blue";
            ["datetime.funny_time"] = "blue";
       
	 }


local already_warned = {}

function co.color(key)
   local c = co.colormap[key]
   if not c then
      if VERBOSE and not already_warned[key] then
	 io.stderr:write("Warning: No color defined in color map for object of type: '",
			 tostring(key),
			 "'\n");
	 already_warned[key] = true;
      end
      c = "black";
   end
   return c, shell_color_table[c]
end

local reset_color_attributes = shell_color_table["none"]

-- key is, e.g. "basic.matchall"
--function color_print(key, list)
--   local cname, ccode = color(key)
--   local text
--   for i, obj in ipairs(list) do
--      text = tostring(obj);
--      io.write(ccode, text, reset_color_attributes, " ");
--   end
--   io.write("\n");
--end

function co.color_print_leaf_nodes(t)
   -- t is a match
   local name, pos, text, subs = common.decode_match(t)
   if (not subs) or (#subs==0) then
      -- already at a leaf node
      local cname, ccode = co.color(name)
      text = tostring(text);			    -- just in case!
      io.write(ccode, text, reset_color_attributes, " ");
   else
      for i = 1, #subs do
	 co.color_print_leaf_nodes(subs[i]);
      end -- for all sub-matches
   end
end

function co.color_write(channel, color, ...)
   channel:write(shell_color_table[color])
   for _,v in ipairs({...}) do
      channel:write(v)
   end
   channel:write(reset_color_attributes)
end

function co.color_string_from_leaf_nodes(t)
   -- t is a match
   if not t then return ""; end
   local output = ""
   local name, pos, text, subs = common.decode_match(t)
   if (not subs) or (#subs==0) then
      -- already at a leaf node
      local cname, ccode = co.color(name)
      text = tostring(text);			    -- just in case!
      return ccode .. text .. reset_color_attributes .. " ";
   else
      for i = 1, #subs do
	 output = output .. co.color_string_from_leaf_nodes(subs[i]);
      end -- for all sub-matches
      return output
   end
end

function co.string_from_leaf_nodes(t)
   -- t is a match
   if not t then return ""; end
   local output = ""
   local name, pos, text, subs = common.decode_match(t)
   if (not subs) or (#subs==0) then
      -- already at a leaf node
      return tostring(text) .. " "		    -- tostring is just in case!
   else
      for i = 1, #subs do
	 output = output .. co.string_from_leaf_nodes(subs[i]);
      end -- for all sub-matches
      return output
   end
end

return co
