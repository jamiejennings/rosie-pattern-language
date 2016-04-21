---- -*- Mode: Lua; -*-                                                                           
----
---- functions for testing 
----
---- © Copyright IBM Corporation 2016.
---- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
---- AUTHOR: Jamie A. Jennings


-- color_write comes from color_output.lua
if not color_write then
   color_write = function(channel, ignore_color, ...)
		    for _,v in ipairs({...}) do
		       channel:write(v)
		    end
		 end
end

local function red_write(...)
   local str = ""
   for _,v in ipairs({...}) do str = str .. tostring(v); end
   color_write(io.stdout, "red", str)
end

test = {}

local count, fail_count, heading_count, subheading_count, messages
local current_heading, current_subheading

function test.start(optional_msg)
   count = 0
   fail_count = 0
   heading_count = 0
   subheading_count = 0
   messages = {}
   current_heading = "Heading not assigned"
   current_subheading = "Subheading not assigned"
   if optional_msg then io.write(optional_msg, "\n"); end
end

function test.check(thing, message)
   count = count + 1
   heading_count = heading_count + 1
   subheading_count = subheading_count + 1
   if not (thing) then
      red_write("X")
      table.insert(messages, {h=current_heading or "Heading unassigned",
			      sh=current_subheading or "",
			      shc=subheading_count,
			      hc=heading_count,
			      c=count,
			      m=message or ""})
      fail_count = fail_count + 1
   else
      io.stdout:write(".")
   end
end

function test.heading(label)
   heading_count = 0
   subheading_count = 0
   current_heading = label
   current_subheading = ""
   io.stdout:write("\n", label, " ")
end

function test.subheading(label)
   subheading_count = 0
   current_subheading = label
   io.stdout:write("\n\t", label, " ")
end

function test.finish(optional_msg)
   io.stdout:write("\n\n** TOTAL ", tostring(count), " tests attempted.\n")
   if fail_count == 0 then
      io.stdout:write("** All tests passed.\n")
   else
      io.stdout:write("** ", tostring(fail_count), " tests failed:\n")
      for _,v in ipairs(messages) do
	 red_write(v.h, ": ", v.sh, ": ", "#", v.shc, " ", v.m, "\n")
      end
   end
   if optional_msg then io.write(optional_msg, "\n"); end
end

return test
