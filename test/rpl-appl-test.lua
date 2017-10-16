-- -*- Mode: Lua; -*-                                                                             
--
-- rpl-appl-test.lua
--
-- © Copyright IBM Corporation 2017.
-- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
-- AUTHOR: Jamie A. Jennings

assert(TEST_HOME, "TEST_HOME is not set")

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
t = e.env:lookup("a")
check(type(t)=="table")

----------------------------------------------------------------------------------------
heading("Testing application of primitive macros")
----------------------------------------------------------------------------------------

heading("Example macros")
subheading("First")

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


subheading("Last")

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

----------------------------------------------------------------------------------------
heading("Find and findall")

p = e:compile('find:a')
ok, m, leftover = e:match(p, "xyzw 1 2 3 aa x x a")
check(ok)
check(m)
check(leftover==7)
check(m.type=="*")
check(m.s==1 and m.e==13)
check(m.subs and m.subs[1] and m.subs[1].s==12 and m.subs[1].e==13)

function test_findall_setup(exp)
   p = e:compile(exp)
   ok, m, leftover = e:match(p, "xyzw 1 2 3 aa x x a")
   check(ok, "call failed", 1)
   check(m, "no match", 1)
   check(leftover==0, "wrong leftover count", 1)
   check(m.type=="*", "wrong match label", 1)
end

function test_findall_1(exp)
   test_findall_setup(exp)
   check(#m.subs==3, "wrong number of submatches", 1)
   check(m.s==1 and m.e==20, "wrong top-level match span", 1)
   check(m.subs and m.subs[1] and m.subs[1].s==12 and m.subs[1].e==13, "wrong sub 1", 1)
   check(m.subs and m.subs[2] and m.subs[2].s==13 and m.subs[2].e==14, "wrong sub 2", 1)
   check(m.subs and m.subs[3] and m.subs[3].s==19 and m.subs[3].e==20, "wrong sub 3", 1)
end

function test_findall_2(exp)
   test_findall_setup(exp)
   check(#m.subs==2, "wrong number of submatches", 1)
   check(m.s==1 and m.e==20, "wrong top-level match span", 1)
   check(m.subs and m.subs[1] and m.subs[1].s==11 and m.subs[1].e==13, "wrong sub 1", 1)
   check(m.subs and m.subs[2] and m.subs[2].s==18 and m.subs[2].e==20, "wrong sub 2", 1)
end

function test_findall_3(exp)
   test_findall_setup(exp)
   check(m.s==1 and m.e==20, "wrong top-level match span", 1)
   check(m.subs and m.subs[1] and m.subs[1].s==18 and m.subs[1].e==20, "wrong sub 1", 1)
end

function test_findall_4(exp)
   test_findall_setup(exp)
   check(#m.subs==2, "wrong number of submatches", 1)
   check(m.s==1 and m.e==20, "wrong top-level match span", 1)
   check(m.subs and m.subs[1] and m.subs[1].s==13 and m.subs[1].e==15, "wrong sub 1", 1)
   check(m.subs and m.subs[2] and m.subs[2].s==19 and m.subs[2].e==20, "wrong sub 2", 1)
end

function test_findall_5(exp)
   test_findall_setup('findall:(a)')
   check(#m.subs==1, "wrong number of submatches", 1)
   check(m.subs and m.subs[1] and m.subs[1].type=="find.*", "wrong top-level match span", 1)
   check(m.subs and m.subs[1] and (m.subs[1].s==18) and (m.subs[1].e==20), "wrong sub 1", 1)
end

test_findall_1('findall:a')
test_findall_1('findall:{a}')

test_findall_5('findall:(a)')

test_findall_2('findall:{~a}')
test_findall_5('findall:(~a)')

test_findall_3('findall:{~a~}')
test_findall_5('findall:(~a~)')

test_findall_4('findall:{a~}')
test_findall_5('findall:(a~)')


----------------------------------------------------------------------------------------
heading("Case sensitivity")
subheading("ci (shallow)")

p, errs = e:compile('ci:"ibm"')
check(p)
if p then
   ok, m, leftover = e:match(p, "IBM")
   check(ok and m and (leftover==0))
   ok, m, leftover = e:match(p, "ibm")
   check(ok and m and (leftover==0))
   ok, m, leftover = e:match(p, "Ibm")
   check(ok and m and (leftover==0))
   ok, m, leftover = e:match(p, "ibM")
   check(ok and m and (leftover==0))
else
   print("compile failed: ")
   table.print(errs, false)
end

function test_foobar()
   p = e:compile('foobar')
   assert(p)
   m, leftover = p:match("foo")
   check(m and (leftover==0), "failed on foo")
   m, leftover = p:match("Foo")
   check(m and (leftover==0), "failed on Foo")
   m, leftover = p:match("fOO")
   check(m and (leftover==0), "failed on fOO")
   m, leftover = p:match("BAR")
   check(m and (leftover==0), "failed on BAR")
   m, leftover = p:match("bar")
   check(m and (leftover==0), "failed on bar")
end

ok = e:load('foobar = ci:("foo" / "bar")')
assert(ok)
test_foobar()

ok = e:load('foobar = ci:{"foo" / "bar"}')
assert(ok)
test_foobar()

ok = e:load('grammar foobar = ci:("foo" / "bar") end')
assert(ok)
test_foobar()

ok = e:load('grammar foobar = ci:{"foo" / "bar"} end')
assert(ok)
test_foobar()

return test.finish()
