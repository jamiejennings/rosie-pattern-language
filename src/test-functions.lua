---- -*- Mode: Lua; -*-                                                                           
----
---- functions for testing 
----
---- © Copyright IBM Corporation 2016, 2017.
---- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
---- AUTHOR: Jamie A. Jennings


co = require("color-output")

-- color_write comes from color_output.lua
color_write = (co and co.color_write) or function(channel, ignore_color, ...)
					    for _,v in ipairs({...}) do
					       channel:write(v)
					    end
					 end


local function red_write(...)
   local str = ""
   for _,v in ipairs({...}) do str = str .. tostring(v); end
   color_write(io.stdout, "red", str)
end

local function green_write(...)
   local str = ""
   for _,v in ipairs({...}) do str = str .. tostring(v); end
   color_write(io.stdout, "green", str)
end

test = {}

function test.current_filename()
   return (debug.getinfo(1).source)
end

local test_filename, count, fail_count, heading_count, subheading_count, messages
local current_heading, current_subheading

function test.start(filename, optional_msg)
   count = 0
   fail_count = 0
   heading_count = 0
   subheading_count = 0
   messages = {}
   current_heading = "Heading not assigned"
   current_subheading = "Subheading not assigned"
   test_filename = filename or "No file name recorded"
   if optional_msg then io.write(optional_msg, "\n"); end
end

function test.check(thing, message, level)
   level = level or 0
   local context = debug.getinfo(2+level, 'lS')
   local line, src = context.currentline, context.short_src
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
			      l=line,
			      src=src,
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

function test.summarize(label, count, fail_count)
   label = label or "TOTAL"
   local total = "\n\n** " .. label .. ": " .. tostring(count) .. " tests attempted.\n"
   if fail_count == 0 then
      green_write(total)
      green_write("** All tests passed.\n")
   else
      io.stdout:write(total)
      io.stdout:write("** ", tostring(fail_count), " tests failed:\n")
   end
end

function test.finish(optional_msg)
   test.summarize("TOTAL", count, fail_count)
   for _,v in ipairs(messages) do
      red_write(v.src, ":", v.l, " ", v.h, ": ", v.sh, ": ", v.m, "\n")
   end
   if optional_msg then io.write(optional_msg, "\n"); end
   -- return everything in case a caller wants to compute a grand total
   return test_filename, count, fail_count, heading_count, subheading_count, messages
end

function test.print_grand_total(results)
   local SHORTFILE, FULLFILE, COUNT, FAILCOUNT = 1, 2, 3, 4
   local count, failcount = 0, 0
   print()
   for _,v in ipairs(results) do
      if #v<=2 then
	 print("File " .. v[1] .. " did not report results")
      else
	 count = count + v[COUNT]
	 failcount = failcount + v[FAILCOUNT]
      end
   end -- for
   test.summarize("GRAND TOTAL", count, failcount)
   return (failcount==0)
end

test.start()					    -- setup defaults so we can get right to testing

return test
