-- -*- Mode: Lua; -*-                                                                             
--
-- rpl-mod-test.lua    test rpl 1.1 modules
--
-- © Copyright IBM Corporation 2017.
-- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
-- AUTHOR: Jamie A. Jennings


-- These tests are designed to run in the Rosie development environment, which is entered with: bin/rosie -D
assert(ROSIE_HOME, "ROSIE_HOME is not set?")
assert(type(rosie)=="table", "rosie package not loaded as 'rosie'?")
import = rosie._env.import
if not test then
   test = import("test")
end

check = test.check
heading = test.heading
subheading = test.subheading

test.start(test.current_filename())

----------------------------------------------------------------------------------------
heading("Import")
----------------------------------------------------------------------------------------

e = rosie.engine.new()
e.searchpath = ROSIE_HOME .. "/test"

ok, _, msgs = e:load("import mod1")
check(ok)
m = e:lookup("mod1")
check(m)
check(m.type=="package")

p = e:lookup("mod1.S")
check(p)
check(p.type=="pattern")

ok, m, left, t0, t1, msgs = e:match("mod1.S", "ababab")
check(ok)
check(m)
check(left==0)
check(type(t0)=="number")
check(type(t1)=="number")
check(not msgs)

-- compile error below, so instead of leftover chars, there is a table of messages
ok, m, left, t0, t1, msgs = e:match("mod1.foooooooo", "ababab")
check(not ok)
check(type(m)=="table")
check(#m==1)






-- return the test results in case this file is being called by another one which is collecting
-- up all the results:
return test.finish()
