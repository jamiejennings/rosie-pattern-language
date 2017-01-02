---- -*- Mode: Lua; -*-                                                                           
----
---- 
----
---- © Copyright IBM Corporation 2016.
---- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
---- AUTHOR: Jamie A. Jennings


function luac(name)
   local luac_bin = ROSIE_HOME .. "/bin/luac"
   return os.execute(luac_bin .. " -o bin/" .. name .. ".luac src/core/" .. name .. ".lua")
end

function compile_system()
   luac("api")
   luac("bootstrap")
   luac("color-output")
   luac("common")
   luac("compile")
   luac("engine")
   luac("eval")
   luac("grep")
   luac("lapi")
   luac("list")
   luac("manifest")
   luac("parse")
   luac("recordtype")
   luac("repl")
   luac("syntax")
   luac("util")
end

function create_lua_package()
   local fn = ROSIE_HOME .. "/rosie.lua"
   local f = io.open(fn, "r")
   if f then
      print("Overwriting " .. fn)
      f:close()
   end
   f, msg = io.open(fn, "w")
   if not f then error(msg); end
   f:write(string.format("dofile(%q)\n", fn))
   f:close()
end

compile_system()
create_lua_package()      -- user can copy rosie.lua to /local/share/lua/5.3/rosie.lua (for example)
