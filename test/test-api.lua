---- -*- Mode: Lua; -*- 
----
---- test-api.lua
----
---- (c) 2016, Jamie A. Jennings
----


if not color_write then
   color_write = function(channel, ignore_color, ...)
		    for _,v in ipairs({...}) do
		       channel:write(v)
		    end
		 end
end

function red_write(...)
   for _,v in ipairs({...}) do color_write(io.stdout, "red", v); end
end

local count = 0
local fail_count = 0
local sub_count = 0
local messages = {}
local current_heading = "Heading not assigned"

function check(thing, message)
   count = count + 1
   sub_count = sub_count + 1
   if not (thing) then
      red_write("X")
      table.insert(messages, {current_heading, sub_count, count, message or ("Test #"..tostring(count))})
      fail_count = fail_count + 1
   end
   io.stdout:write(".")
end

function heading(label)
   sub_count = 0
   current_heading = label
   io.stdout:write("\n", label, " ")
end

function ending()
   io.stdout:write("\n\n** TOTAL ", tostring(count), " tests attempted.\n")
   if fail_count == 0 then
      io.stdout:write("** All tests passed.\n")
   else
      io.stdout:write("** ", tostring(fail_count), " tests failed:\n")
      for _,v in ipairs(messages) do
	 red_write(v[1], ": ", "#", v[2], " ", v[4], "\n")
      end
   end
end

----------------------------------------------------------------------------------------

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
check(false, "This is a test of the test harness")

heading("Match")



ending()




       

