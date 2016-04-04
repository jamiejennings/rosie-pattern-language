---- -*- Mode: Lua; -*- 
----
---- test-api.lua
----
---- (c) 2016, Jamie A. Jennings
----

local count = 0

function check(thing, message)
   assert(thing, message)
   io.stdout:write(".")
   count = count + 1
end

function heading(label)
   io.stdout:write("\n", label, " ")
end

function ending()
   io.stdout:write("\nDone.\n", tostring(count), " tests complete.\n")
end

heading("Require api")
api = require "api"

check(type(api)=="table")
check(api.VERSION)
check(type(api.VERSION=="string"))

heading("Engine")
check(api.new_engine)
check(api.ping_engine)
check(api.delete_engine)
check(api.get_env)

heading("Load")
check(api.load_string)
check(api.load_file)
check(api.load_manifest)

heading("Match")



ending()




       

