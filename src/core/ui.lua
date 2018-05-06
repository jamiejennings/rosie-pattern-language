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
function ui.properties(name, obj, colorstring)
   if common.pattern.is(obj) then
      local kind = "pattern"
      local capture = (not obj.alias)
      local binding = obj.ast and ast.tostring(obj.ast) or tostring(obj)
      local color, reason = co.query(name, colorstring)
      local color_explanation = color
      local origin = obj.ast and obj.ast.sourceref and obj.ast.sourceref.origin
      return {name=name,
	      type=kind,
	      capture=capture,
	      color=color_explanation,
	      binding=binding,
	      source=origin and (origin.importpath or origin.filename)}
   elseif environment.is(obj) then
      local origin = obj.origin
      return {name=name,
	      type="package",
	      color="",
	      binding=tostring(obj),
	      source=origin and origin.filename}
   elseif common.pfunction.is(obj) then
      local origin = obj.ast and obj.ast.sourceref and obj.ast.sourceref.origin
      return {name=name,
	      type="function",
	      color="",
	      binding=tostring(obj),
	      source=origin and (origin.importpath or origin.filename)}
   elseif common.macro.is(obj) then
      local origin = obj.ast and obj.ast.sourceref and obj.ast.sourceref.origin
      return {name=name,
	      type="macro",
	      color="",
	      binding=tostring(obj),
	      source=origin and (origin.importpath or origin.filename)}
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
   out[1] = count				    -- ugh.
   out[2] = total
   return out
end   

local function shorten(str, len)
   if #str > len then
      return "..." .. str:sub(#str-len+4)
   end
   return str
end
   
function ui.to_property_table(env, filter, colorstring)
   assert(environment.is(env))
   assert(type(filter)=="string")
   local pkgname, localname = common.split_id(filter)
   if not pkgname then
      local tbl = environment.all_bindings(env)
      for k,v in pairs(tbl) do tbl[k] = ui.properties(k,v,colorstring); end
      return apply_filter(tbl, localname)
   end
   local pkgenv = env:lookup(pkgname)
   if pkgenv then
      local props = ui.properties(pkgname, pkgenv)
      if props.type=="package" then
	 local tbl = environment.exported_bindings(pkgenv)
	 for k,v in pairs(tbl) do
	    tbl[k] = ui.properties(common.compose_id{pkgname, k}, v, colorstring)
	 end
	 return apply_filter(tbl, localname)
      else
	 return nil, "Type error: expected a package, found a " .. props.type
      end
   else
      if pkgname=="*" then
	 return nil, "Wildcard for package name not supported"
      end
      return nil, "Package '" .. pkgname .. "' not loaded"
   end
end

function ui.print_props(tbl, skip_header)
   local count, total = tbl[1], tbl[2]		    -- ugh.
   local fmt = "%-24s %-4s %-8s %-15s %s"
   if not skip_header then
      print();
      print(string.format(fmt, "Name", "Cap?", "Type", "Color", "Source"))
      print("------------------------ ---- -------- --------------- -------------------------")
   end
   local kind, color, cap
   local s, e

   local names = {}
   for k,v in pairs(tbl) do if type(k)=="string" then table.insert(names, k); end; end
   table.sort(names)

   for _,v in ipairs(names) do
      local color = tbl[v].color
      local cap = (tbl[v].capture and "Yes" or "")
--      local source = shorten(tbl[v].source or "", 36)
      local source = tbl[v].source or ""
      print(string.format(fmt, v, cap, tbl[v].type, color, source))
   end
   if not skip_header then
      print()
      print(count .. "/" .. total .. " names shown")
   end
end


return ui
