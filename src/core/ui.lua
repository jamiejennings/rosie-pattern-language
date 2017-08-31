-- -*- Mode: Lua; -*-                                                                             
--
-- ui.lua    UI-specific code
--
-- © Copyright IBM Corporation 2017.
-- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
-- AUTHOR: Jamie A. Jennings


local ui = {}

local co = require "color"


local function reconstitute_pattern_definition(id, p)
   if p then
      if recordtype.parent(p.ast) then
	 -- We have an ast, not a parse tree
	 return ast.tostring(p.ast) or "built-in RPL pattern"
      end
      return (p.ast and writer.reveal_ast(p.ast)) or "// built-in RPL pattern //" 
   end
   engine_error(e, "undefined identifier: " .. id)
end

-- FUTURE: Update this to make a general pretty printer for the contents of the environment.
function ui.properties(name, obj)
   if common.pattern.is(obj) then
      local kind = "pattern"
      local capture = (not obj.alias)
      local binding = reconstitute_pattern_definition(name, obj)
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
      return {name=name, type="package", color="", binding=tostring(obj)}
   elseif common.pfunction.is(obj) then
      return {name=name, type="function", color="", binding=tostring(obj)}
   elseif common.macro.is(obj) then
      return {name=name, type="macro", color="", binding=tostring(obj)}
   else
      error("Internal error: unknown object, stored at " ..
	    tostring(name) .. ": " .. tostring(obj))
   end
end

-- Lookup an identifier in the engine's environment, and get a human-readable definition of it
-- (reconstituted from its ast).  If identifier is null, return the entire environment.
local function lookup(en, identifier)
   assert(type(identifier)=="string", "missing identifier argument (string)?")

   local env = en.env
   if identifier then
      local prefix, localname = common.split_id(identifier)
      local val = lookup(en.env, localname, prefix)
	 return val and ui.properties(identifier, val)
   end
   local flat_env = environment.flatten(env)
   -- Rewrite the flat_env table, replacing the pattern with a table of properties
   for id, pat in pairs(flat_env) do flat_env[id] = ui.properties(id, pat); end
   return flat_env
end

function ui.remove_binding(en, identifier)
   assert(type(identifier)=="string", "missing identifier argument (string)?")
   if environment.lookup(en.env, identifier) then
      environment.bind(en.env, identifier, nil)
      return true
   else
      return false
   end
end





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

   local fmt = "%-30s %-4s %-10s %-15s %s"

   if not skip_header then
      print();
      print(string.format(fmt, "Name", "Cap?", "Type", "Color", "Source"))
      print("------------------------------ ---- ---------- ---------------")
   end
   local kind, color, cap
   local s, e
   for _,v in ipairs(pattern_list) do
      if filter then s, e = string.find(string.lower(tostring(v)), filter); end
      if (not filter) or s then
	 local color = flat_env[v].color
	 local cap = (flat_env[v].capture and "Yes" or "")
	 local source = flat_env[v].source or ""
	 print(string.format(fmt, v, cap, flat_env[v].type, color, source))
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
