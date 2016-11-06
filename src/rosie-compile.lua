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

compile_system()
