-- -*- Mode: Lua; -*-                                                                             
--
-- ui.lua    UI-specific code
--
-- © Copyright IBM Corporation 2017.
-- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
-- AUTHOR: Jamie A. Jennings


local ui = {}

local co = require "color"
local environment = require "environment"

-- FUTURE: Update this to make a general pretty printer for the contents of the environment.
function ui.properties(name, obj)
   if common.pattern.is(obj) then
      local kind = "pattern"
      local capture = (not obj.alias)
      local binding = obj.ast and ast.tostring(obj.ast) or "built-in"
      local color, reason = co.query(name)
      local color_explanation = color
      if reason=="default" then color_explanation = color_explanation .. " (default)"; end
      local origin = obj.ast and obj.ast.sourceref and obj.ast.sourceref.origin
      local source = origin and origin.filename
      return {name=name,
	      type=kind,
	      capture=capture,
	      color=color_explanation,
	      binding=binding,
	      source=source}
   elseif environment.is(obj) then
      return {name=name,
	      type="package",
	      color="",
	      binding=tostring(obj),
	      source=(obj.origin and obj.origin.filename)}
   elseif common.pfunction.is(obj) then
      return {name=name,
	      type="function",
	      color="",
	      binding=tostring(obj)}
   elseif common.macro.is(obj) then
      return {name=name,
	      type="macro",
	      color="",
	      binding=tostring(obj)}
   else
      error("Internal error: unknown object, stored at " ..
	    tostring(name) .. ": " .. tostring(obj))
   end
end

local function filter_match(key, filter)
   if filter == "*" then
      return true
   else
      return key==filter			    -- TEMP
   end
end
   
local function apply_filter(tbl, name_filter)
   local out = {}
   local count, total = 0, 0
   for k,v in pairs(tbl) do
      total = total + 1
      if filter_match(k, name_filter) then
	 count = count + 1;
	 out[k] = v;
      end
   end
   return out, count, total
end   

local function shorten(str, len)
   if #str > len then
      return "..." .. str:sub(#str-len+4)
   end
   return str
end
   
function ui.print_env(tbl, filter, skip_header)
   local tbl, count, total = apply_filter(tbl, filter)
   local fmt = "%-30s %-4s %-10s %-15s %s"
   if not skip_header then
      print();
      print(string.format(fmt, "Name", "Cap?", "Type", "Color", "Source"))
      print("------------------------------ ---- ---------- --------------- ------------------------------")
   end
   local kind, color, cap
   local s, e

   local names = {}
   for k,v in pairs(tbl) do table.insert(names, k); end
   table.sort(names)

   for _,v in ipairs(names) do
      local color = tbl[v].color
      local cap = (tbl[v].capture and "Yes" or "")
      local source = shorten(tbl[v].source or "", 30)
      print(string.format(fmt, v, cap, tbl[v].type, color, source))
   end
   if not skip_header then
      print()
      if filter then print(count .. "/" .. total .. " names shown")
      else print(total .. " names"); end
   end
end


return ui
