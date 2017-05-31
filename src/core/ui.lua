-- -*- Mode: Lua; -*-                                                                             
--
-- environment.lua    UI-specific code
--
-- © Copyright IBM Corporation 2017.
-- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
-- AUTHOR: Jamie A. Jennings



local ui = {}

local co = require "color-output"

function ui.print_env(flat_env, filter, skip_header, total)
   -- print a sorted list of patterns contained in the flattened table 'flat_env'
   local pattern_list = {}

   local n = next(flat_env)
   while n do
      table.insert(pattern_list, n)
      n = next(flat_env, n);
   end
   table.sort(pattern_list)
   local patterns_loaded = #pattern_list
   total = (total or 0) + patterns_loaded
   local filter = filter and string.lower(filter) or nil
   local filter_total = 0

   local fmt = "%-30s %-4s %-10s %-8s"

   if not skip_header then
      print();
      print(string.format(fmt, "Name", "Cap?", "Type", "Color"))
      print("------------------------------ ---- ---------- --------")
   end
   local kind, color, cap
   local s, e
   for _,v in ipairs(pattern_list) do
      if filter then s, e = string.find(string.lower(tostring(v)), filter); end
      if (not filter) or s then
	 color = co.colormap[v] or ""
	 cap = (flat_env[v].capture and "Yes" or "")
	 print(string.format(fmt, v, cap, flat_env[v].type, color))
	 filter_total = filter_total + 1
      end
   end
   if patterns_loaded==0 then
      print("<empty>");
   end
   if not skip_header then
      print()
      if filter then print(filter_total .. " / " .. total .. " names shown")
      else print(total .. " names"); end
   end
end


return ui
