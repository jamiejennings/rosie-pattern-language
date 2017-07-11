-- -*- Mode: Lua; -*-                                                                             
--
-- rpl-appl-test.lua
--
-- © Copyright IBM Corporation 2017.
-- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
-- AUTHOR: Jamie A. Jennings

-- These tests are designed to run in the Rosie development environment, which is entered with: bin/rosie -D
assert(ROSIE_HOME, "ROSIE_HOME is not set?")
assert(type(rosie)=="table", "rosie package not loaded as 'rosie'?")
import = rosie.import
if not test then
   test = import("test")
end

check = test.check
heading = test.heading
subheading = test.subheading

e = false;
global_rplx = false;

function set_expression(exp)
   global_rplx = e:compile(exp)
end

function check_match(exp, input, expectation, expected_leftover, expected_text, addlevel)
   expected_leftover = expected_leftover or 0
   addlevel = addlevel or 0
   set_expression(exp)
   local m, leftover = global_rplx:match(input)
   check(expectation == (not (not m)), "expectation not met: " .. exp .. " " ..
	 ((m and "matched") or "did NOT match") .. " '" .. input .. "'", 1+addlevel)
   local fmt = "expected leftover matching %s against '%s' was %d but received %d"
   if m then
      check(leftover==expected_leftover,
	    string.format(fmt, exp, input, expected_leftover, leftover), 1+addlevel)
      if expected_text and m then
	 local name, pos, text, subs = common.decode_match(m)
	 local fmt = "expected text matching %s against '%s' was '%s' but received '%s'"
	 check(expected_text==text,
	       string.format(fmt, exp, input, expected_text, text), 1+addlevel)
      end
   end
   return m, leftover
end
      
test.start(test.current_filename())

----------------------------------------------------------------------------------------
heading("Setting up")
----------------------------------------------------------------------------------------

check(type(rosie)=="table")
e = rosie.engine.new("rpl appl test")
check(rosie.engine.is(e))

subheading("Setting up assignments")
success, pkg, msg = e:load('a = "a"  b = "b"  c = "c"  d = "d"')
check(type(success)=="boolean")
check(pkg==nil)
check(type(msg)=="table")
t = e:lookup("a")
check(type(t)=="table")

----------------------------------------------------------------------------------------
heading("Testing application of primitive macros")
----------------------------------------------------------------------------------------

subheading("Example macro: first")

p, msg = e:compile('first:a')
check(p)
if not p then print("*** compile failed: "); table.print(msg); end
ok, m, leftover = e:match(p, "a")
check(ok)
check(type(m)=="table")
check(type(leftover)=="number" and leftover==0)
check(m.type=="a")

p = e:compile('first:(a, b)')			    -- 2 args
ok, m, leftover = e:match(p, "a")
check(ok)
check(type(m)=="table")
check(type(leftover)=="number" and leftover==0)
check(m.type=="a")

p = e:compile('first:(a b, b b)')		    -- 2 args
ok, m, leftover = e:match(p, "a b")
check(ok)
check(m and m.type=="*")
check(type(leftover)=="number" and leftover==0)
ok, m, leftover = e:match(p, "b b")
check(ok)
check(not m)

p = e:compile('first:{a b, b b}')		    -- 2 args
ok, m, leftover = e:match(p, "a b")
check(ok)
check(not m)
ok, m, leftover = e:match(p, "ab")
check(ok)
check(m and m.type=="*")
check(type(leftover)=="number" and leftover==0)
ok, m, leftover = e:match(p, "b b")
check(ok)
check(not m)
ok, m, leftover = e:match(p, "bb")
check(ok)
check(not m)

p = e:compile('first:(a b)')			    -- one arg
ok, m, leftover = e:match(p, "a")
check(ok)
check(not m)
ok, m, leftover = e:match(p, "ab")
check(ok)
check(not m)
ok, m, leftover = e:match(p, "a b")
check(ok)
check(m and m.type=="*")
check(leftover==0)
ok, m, leftover = e:match(p, "a bXYZ")
check(ok)
check(m and m.type=="*")
check(leftover==3)

p = e:compile('first:{a b}')			    -- one arg
ok, m, leftover = e:match(p, "a b")
check(ok)
check(not m)
ok, m, leftover = e:match(p, "abX")
check(ok)
check(m and m.type=="*")
check(leftover==1)

p = e:compile('first:(a/b)')			    -- one arg
ok, m, leftover = e:match(p, "a b")
check(ok)
check(m and m.type=="*")
check(leftover==2)
ok, m, leftover = e:match(p, "bX")
check(ok)
check(m and m.type=="*")
check(leftover==1)

p = e:compile('first:{a/b}')			    -- one arg
ok, m, leftover = e:match(p, "a b")
check(ok)
check(m and m.type=="*")
check(leftover==2)
ok, m, leftover = e:match(p, "bX")
check(ok)
check(m and m.type=="*")
check(leftover==1)

p = e:compile('first:"hi"')			    -- one arg
ok, m, leftover = e:match(p, "a b")
check(ok)
check(not m)
ok, m, leftover = e:match(p, "hi")
check(ok)
check(m and m.type=="*")
check(leftover==0)


subheading("Example macro: last")

p = e:compile('last:a')
ok, m, leftover = e:match(p, "a")
check(ok)
check(type(m)=="table")
check(type(leftover)=="number" and leftover==0)
check(m and m.type=="a")

p = e:compile('last:(a, b)')			    -- 2 args
ok, m, leftover = e:match(p, "a")
check(ok)
check(not m)
ok, m, leftover = e:match(p, "b")
check(ok)
check(type(m)=="table")
check(type(leftover)=="number" and leftover==0)
check(m and m.type=="b")

p = e:compile('last:(a b, b b)')		    -- 2 args
ok, m, leftover = e:match(p, "a b")
check(ok)
check(not m)
ok, m, leftover = e:match(p, "b b")
check(ok)
check(m and m.type=="*")
check(type(leftover)=="number" and leftover==0)
ok, m, leftover = e:match(p, "bb")
check(ok)
check(not m)

p = e:compile('last:{a b, b b}')		    -- 2 args
ok, m, leftover = e:match(p, "a b")
check(ok)
check(not m)
ok, m, leftover = e:match(p, "ab")
check(ok)
check(not m)
ok, m, leftover = e:match(p, "bb")
check(ok)
check(m and m.type=="*")
check(type(leftover)=="number" and leftover==0)
ok, m, leftover = e:match(p, "b b")
check(ok)
check(not m)


subheading("Example macro: find")

p = e:compile('find:a')
ok, m, leftover = e:match(p, "xyzw 1 2 3 a")
check(ok)
check(m)
check(leftover==0)
check(m.type=="*")
check(m.s==1 and m.e==13)
check(m.subs and m.subs[1] and m.subs[1].s==12 and m.subs[1].e==13)

return test.finish()
