-- -*- Mode: Lua; -*-                                                                             
--
-- rpl-appl-test.lua
--
-- © Copyright IBM Corporation 2017.
-- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
-- AUTHOR: Jamie A. Jennings

assert(TEST_HOME, "TEST_HOME is not set")

list = import "list"
violation = import "violation"

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

--[[
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

--]]

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

p = e:compile('find:("quick" ("brown" / "blue") "fox")')
check(p)
lines = io.lines("test/quick.txt")
answers = {false, true, true, true, true, false, false}
i = 1
for line in lines do
   ok, m, leftover = e:match(p, line)
   check(ok, "call failed", 1)
   if answers[i] then
      check(m, "failed to match where it should")
   else
      check(not m, "matched where it should have failed to match")
   end
   i = i + 1
end


----------------------------------------------------------------------------------------
heading("Message and halt")
subheading("Message")

function test_message(exp, input)
   p, errs = e:compile(exp)
   check(p, "failed to compile", 1)
   if not p then
      print()
      print(table.concat(list.map(violation.tostring, errs), '\n'))
      m = nil
   else
      ok, m, leftover = e:match(p, input)
      check(ok, "match failed to execute", 1)
      check(m and m.type=="*", "either match failed or wrong match type (at top level)", 1)
   end
end

test_message('message:#Hello', "")
check(m.data=="")
check(#m.subs==1)
check(m.subs[1].type=="message" and m.subs[1].data=="Hello")
check(leftover==0)

test_message('message:#Hello', "abc")
check(m.data=="")
check(#m.subs==1)
check(m.subs[1].type=="message" and m.subs[1].data=="Hello")
check(leftover==3)

test_message('{"ab" message:#Hello}', "abc")
check(m.data=="ab")
check(#m.subs==1)
check(m.subs[1].type=="message" and m.subs[1].data=="Hello")
check(leftover==1)

test_message('"abc" message:#Hello', "abc")
check(m.data=="abc")
check(#m.subs==1)
check(m.subs[1].type=="message" and m.subs[1].data=="Hello")
check(leftover==0)

test_message('"abc" message:#Hello', "abc def")
check(m.data=="abc ")
check(#m.subs==1)
check(m.subs[1].type=="message" and m.subs[1].data=="Hello")
check(leftover==3)

test_message('"abc" message:#Hello "def"', "abc def")
check(m.data=="abc def")
check(#m.subs==1)
check(m.subs[1].type=="message" and m.subs[1].data=="Hello")
check(leftover==0)

test_message('"abc" / message:#Hello', "abc")
check(m.data=="abc")
check(m.subs==nil)
check(leftover==0)

test_message('"abc" / message:#Hello', "ab")
check(m.data=="")
check(#m.subs==1)
check(m.subs[1].type=="message" and m.subs[1].data=="Hello")
check(leftover==2)

p, errs = e:compile('(message:#Hello)')
check(p)
p, errs = e:compile('message:(#Hello)')
check(p)
p, errs = e:compile('message:{#Hello}')
check(p)

p, errs = e:compile('(message:#Hello)+')
check(not p)
msg = table.concat(list.map(violation.tostring, errs), '\n')
check(msg:find('can match the empty string'))
p, errs = e:compile('{message:#Hello}?')
check(not p)
check(type(errs)=="table")
msg = table.concat(list.map(violation.tostring, errs), '\n')
check(msg)
if msg then check(msg:find('can match the empty string')); end

subheading("Message inside brackets")

p, errs = e:compile('[[]message:#Hello]')
check(p)
if not p then print("ERRORS ARE"); table.print(errs); end
ok, m, leftover = e:match(p, "")
check(ok)
check(m)
check(m.type=="*")
check(m.subs and m.subs[1] and m.subs[1].type=="message")

test_message('[[a]message:#Hello]', "a")
check(m.data=="a")
check(m.subs==nil)
check(leftover==0)


--[[ Removed halt on Tuesday, January 16, 2018 because it's not useful by itself.
subheading("Halt")

function test_halt(exp, input)
   p, errs = e:compile(exp)
   check(p, "failed to compile", 1)
   if not p then
      print()
      print(table.concat(list.map(violation.tostring, errs), '\n'))
      m = nil
   else
      ok, m, leftover, abend = e:match(p, input)
      check(ok, "match failed to execute", 1)
   end
end

test_halt('halt', "")
check(m==nil)
check(abend==true)

test_halt('halt', "abc")
check(m==nil)
check(abend==true)
check(leftover==3)

test_halt('"abc" halt', "abc")
check(m)
if m then
   check(m.type=="*")
   check(not m.subs)
   check(m.s==1)
   check(m.e==4)
   check(m.data=="abc")
end
check(abend==true)
check(leftover==0)

test_halt('"abc" "def" / halt', "abc")
check(m)
if m then
   check(m.type=="*")
   check(not m.subs)
   check(m.s==1)
   check(m.e==4)
   check(m.data=="abc")
end
check(abend==true)
check(leftover==0)

test_halt('"abc" "def" / halt', "abc def")
check(m)
if m then
   check(m.type=="*")
   check(not m.subs)
   check(m.s==1)
   check(m.e==8)
   check(m.data=="abc def")
end
check(abend==false)
check(leftover==0)

test_halt('"abc" ("def" / halt) "xyz"', "abc def xyz")
check(m)
if m then
   check(m.type=="*")
   check(not m.subs)
   check(m.s==1)
   check(m.e==12)
   check(m.data=="abc def xyz")
end
check(abend==false)
check(leftover==0)

test_halt('"abc" ("def" / halt) "xyz"', "abc xyz")
check(m)
if m then
   check(m.type=="*")
   check(not m.subs)
   check(m.s==1)
   check(m.e==5)
   check(m.data=="abc ")
end
check(abend==true)
check(leftover==3)

test_halt('"abc" ("def" / halt) "xyz"', "abc ZZZ")
check(m)
if m then
   check(m.type=="*")
   check(not m.subs)
   check(m.s==1)
   check(m.e==5)
   check(m.data=="abc ")
end
check(abend==true)
check(leftover==3)

test_halt('"abc" ("defg" / halt) "xyz"', "abc def xyz")
check(m)
if m then
   check(m.type=="*")
   check(not m.subs)
   check(m.s==1)
   check(m.e==5)
   check(m.data=="abc ")
end
check(abend==true)
check(leftover==7)

--]]


----------------------------------------------------------------------------------------
heading("Case sensitivity")
subheading("ci literals (shallow test)")

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
   check(m and (leftover==0), "failed on foo", 1)
   m, leftover = p:match("Foo")
   check(m and (leftover==0), "failed on Foo", 1)
   m, leftover = p:match("fOO")
   check(m and (leftover==0), "failed on fOO", 1)
   m, leftover = p:match("BAR")
   check(m and (leftover==0), "failed on BAR", 1)
   m, leftover = p:match("bar")
   check(m and (leftover==0), "failed on bar", 1)
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


subheading("ci named character sets (shallow test)")

function check_match(exp, input)
   p, errs = e:compile(exp)
   check(p, "compilation failed", 1)
   if p then
      ok, m, leftover = e:match(p, input)
      check(ok and m and (leftover==0), "match failed", 1)
   else
      print("compile failed: ")
      table.print(errs, false)
   end
end

check_match('ci:[:upper:]+', 'ABCDEF')
check_match('ci:[:upper:]+', 'abcdef')
check_match('ci:[:upper:]+', 'ABcdeF')
check_match('ci:[:lower:]+', 'ABCDEF')
check_match('ci:[:lower:]+', 'abcdef')
check_match('ci:[:lower:]+', 'ABcdeF')
check_match('ci:[:alpha:]+', 'ABCDEF')
check_match('ci:[:alpha:]+', 'abcdef')
check_match('ci:[:alpha:]+', 'ABcdeF')
check_match('ci:[:punct:]+', '-!@#$|()')


subheading("ci list character sets (shallow test)")

check_match('ci:[A]{2}', 'Aa')
check_match('ci:[a]{2}', 'Aa')
check_match('ci:[ABc]+', 'aAbBcC')
check_match('ci:[+/x]+', 'XXxX++/')


subheading("ci range character sets (shallow test)")

check_match('ci:[A-C]+', 'AaCc')
check_match('ci:[x-z]{6}', 'XYZyzx')
check_match('ci:[C-a]+', 'aAcC')
check_match('ci:[C-a]+', 'CDEcdexyzAa')

p = e:compile('ci:[C-a]+'); check(p)
ok, m, leftover = e:match(p, 'Ab')
check(ok)
check(m)
check(leftover == 1)
ok, m, leftover = e:match(p, 'B')
check(ok)
check(not m)

check_match('ci:[+-|]+', 'ABCabc+/xyzXYZ{') --}
check_match('ci:[+-C]+', '+/ABCabc')
check_match('ci:[x-|]+', 'XYZxyz{|') --}

p = e:compile('ci:[+-C]+'); check(p)
ok, m, leftover = e:match(p, 'abcD')
check(ok)
check(m)
check(leftover == 1)
ok, m, leftover = e:match(p, 'abcd')
check(ok)
check(m)
check(leftover == 1)

check_match('ci:[[CD] [Z-a]]+', 'DCcdzZAa')
p = e:compile('ci:[[CD] [Z-a]]+'); check(p)
ok, m, leftover = e:match(p, 'b')
check(ok); check(not m)

check_match('[[CD] ci:[Z-a]]+', 'DCzA')
p = e:compile('[[CD] ci:[Z-a]]+'); check(p)
ok, m, leftover = e:match(p, 'c')
check(ok); check(not m)


-- Testing the shallowness, i.e. the macro does not affect identifiers

ok = e:load('foobar = "foobar"'); check(ok)
p = e:compile('ci:foobar'); check(p)
ok, m, leftover = e:match(p, 'foobar')
check(ok); check(m); check(leftover == 0)
ok, m, leftover = e:match(p, 'Foobar')
check(ok); check(not m)

p = e:compile('ci:(foobar "Hi")'); check(p)
ok, m, leftover = e:match(p, 'foobar HI')
check(ok); check(m); check(leftover == 0)
ok, m, leftover = e:match(p, 'foobar hi')
check(ok); check(m); check(leftover == 0)
ok, m, leftover = e:match(p, 'Foobar Hi')
check(ok); check(not m)


--[[
subheading("ci (deep test)")

ok = e:load('foo = {"foo" / "bar"}')
assert(ok)
ok = e:load('foobar = ci:foo')
assert(ok)
test_foobar()
--]]

return test.finish()
