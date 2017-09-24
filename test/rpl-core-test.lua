---- -*- Mode: Lua; -*- 
----
---- rpl-core-test.lua
----
---- (c) 2016, 2017, Jamie A. Jennings
----

-- TODO:
-- test repetition where min > max
-- test repetition where max==0


assert(TEST_HOME, "TEST_HOME is not set")

list = import "list"
cons, map, flatten, member = list.cons, list.map, list.flatten, list.member
common = import "common"
violation = import "violation"

check = test.check
heading = test.heading
subheading = test.subheading

e = false;

global_rplx = false;

function set_expression(exp)
   global_rplx, msg = e:compile(exp)
   if not global_rplx then
      print("\nThis exp failed to compile: " .. tostring(exp))
      table.print(msg)
      error("compile failed in rpl-core-test")
   end
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
e = rosie.engine.new("rpl core test")
check(rosie.engine.is(e))

subheading("Setting up assignments")
success, pkgname, msg = e:load('a = "a"  b = "b"  c = "c"  d = "d"')
check(type(success)=="boolean")
check(not pkgname)
check(type(msg)=="table")
t = e.env:lookup("a")
check(type(t)=="table")

set_expression('a')
ok, match, leftover = e:match('a', "a")
check(ok)
check(type(match)=="table")
check(type(leftover)=="number")
check(leftover==0)
check(match.type=="a", "the match of an identifier is named for the identifier")

   set_expression('(a)')
   ok, match, leftover = e:match('(a)', "a")
   check(ok)
   check(match.type=="*", "the match of an expression is anonymous")
   check(match.subs and match.subs[1] and match.subs[1].type=="a")

   set_expression('{a}')
   ok, match, leftover = e:match('{a}', "a")
   check(ok)
   check(match.type=="*", "the match of an expression is anonymous")
   check(match.subs and match.subs[1] and match.subs[1].type=="a")

ok, pkgname, msg = e.load(e, 'alias plain_old_alias = "p"')
check(ok)

ok, pkgname, msg = e.load(e, 'alias alias_to_plain_old_alias = plain_old_alias')
check(ok)

ok, pkgname, msg = e.load(e, 'alias alias_to_a = a')
check(ok)

ok, pkgname, msg = e.load(e, 'alternate_a = a')
check(ok)

ok, pkgname, msg = e.load(e, 'alternate_to_alias_to_a = alias_to_a')
check(ok)

ok, pkgname, msg = e.load(e, 'alias alias_to_alternate_to_alias_to_a = alias_to_a')
check(ok)

ok, pkgname, msg = e.load(e, 'uses_a = a a')
check(ok)

ok, pkgname, msg = e.load(e, 'alternate_uses_a = uses_a')
check(ok)

ok, pkgname, msg = e.load(e, 'alias alias_to_uses_a = uses_a')
check(ok)

subheading("Checking for required parse failures")
ok = e:compile(".")
check(ok)
ok = e:compile("..")
check(ok)
ok = e:compile(".~")
check(ok)
ok = e:compile("a.")
check(not ok)
ok = e:compile(".a")
check(not ok)
ok = e:compile("a.*")
check(not ok)
ok = e:compile("a .*")
check(ok)
ok = e:compile("a.b.c")
check(not ok)

subheading("Testing re-assignments")

check_match('plain_old_alias', "x", false, 1)
result = check_match('plain_old_alias', "p", true)
check(result.type=="*", "the match of an alias is anonymous")
check(not result.subs, "no subs")

check_match('alias_to_plain_old_alias', "x", false, 1)
result = check_match('alias_to_plain_old_alias', "p", true)
check(result.type=="*", "the match of an alias is anonymous")
check(not result.subs, "no subs")

match = check_match('alias_to_a', "a", true)
check(match.type=="*", 'an alias can be used as a top-level exp, and the match is labeled "*"')
check(match.subs and match.subs[1] and match.subs[1].type=="a")

match = check_match('alternate_a', "a", true)
check(match.type=="alternate_a", 'the match is labeled with the identifier name to which it is bound')
subs = match.subs
check(not subs)

match = check_match('alternate_to_alias_to_a', "a", true)
check(match.type=="alternate_to_alias_to_a", 'rhs of an assignment can contain an alias, and it will be captured')
subs = match.subs
check(not subs)

match = check_match('alias_to_alternate_to_alias_to_a', "a", true)
check(match.type=="*", 'an alias can be used as a top-level exp, and the match is labeled "*"')
subs = match.subs
check(subs and subs[1] and subs[1].type=="a")

match = check_match('uses_a', "a a", true)
check(match.type=="uses_a", 'the match is labeled with the identifier name to which it is bound')
subs = match.subs
check(subs and #subs==2)
check(subs[1].type=="a")
check(subs[2].type=="a")

match = check_match('alias_to_uses_a', "a a", true)
check(match.type=="*", 'an alias can be used as a top-level exp, and the match is labeled "*"')
subs = match.subs
check(subs and #subs==1 and (subs[1].type=="uses_a"))
subs = match.subs[1].subs
check(subs and #subs==2)
check(subs[1] and (subs[1].type=="a"))
check(subs[2] and (subs[2].type=="a"))

----------------------------------------------------------------------------------------
heading("Literals")
----------------------------------------------------------------------------------------
subheading("Built-ins")

set_expression('.')
ok, match, leftover = e:match('.', "a")
check(ok)
check(match.type=="*", "the match of an alias is anonymous")

check_match(".", "a", true)
check_match(".", "abcd", true, 3, "a")
check_match("(.)", "abcd", true, 3, "a")
check_match("{.}", "abcd", true, 3, "a")
check_match(".~", "abcd", false)
check_match("(.~)", "abcd", false)
check_match("{.~}", "abcd", false)

check_match(".", "1", true)
check_match(".", "\n", true)
check_match(".", "!", true)
check_match(".", "", false)
check_match("$", "", true)
check_match("$", "a", false, 1)
check_match("$", "\t", false)
check_match("~", " ", true)
check_match("~", ",", true, 1)
check_match("~", "", true)

subheading("Strings")
check_match('"Hello"', "Hello", true)
check_match('"Hello"', "Hello!", true, 1)
check_match('"Hello"', " Hello!", false)
check_match('"Hello, world!"', "Hello, world!", true)
check_match('"Hello"', "", false)
check_match('""', "", true)
check_match('" "', "", false)

----------------------------------------------------------------------------------------
heading("Sequences")
----------------------------------------------------------------------------------------
subheading("With built-ins and literals")
check_match('.*', " Hello\n", true)
check_match('. . .', "Hello", false)
check_match('. . .', "H e llo", true, 2)
check_match('(. . .)', "H e llo", true, 2)
check_match('(. . .)', "H e l lo", true, 3)
check_match('{. . .}', "H e llo", true, 4, "H e")
check_match('.*.', "Hello", false)
check_match('"hi" "there"', "hi there", true)
check_match('("hi" "there")', "hi there", true)
check_match('{"hi" "there"}', "hi there", false)
check_match('"hi" "there"', "hi there lovely", true, 7)
check_match('"hi" "there"', "hi\nthere", true)
check_match('"hi" "there"', "hi\n\t\t    there ", true, 1, "hi\n\t\t    there")
check_match('"hi" "there"', "hithere", false)

----------------------------------------------------------------------------------------
heading("Alternation (choice)")
----------------------------------------------------------------------------------------
check_match('a / b', "", false)
check_match('a / b', "x", false)
check_match('a / b', "a", true, 0, "a")
check_match('a / b', "ab", true, 1)
check_match('a / b', "a b", true, 2, "a")
check_match('a / b', "ba", true, 1)
check_match('a / b', "b a", true, 2, "b")
check_match('a / b', "b b", true, 2, "b")
check_match('a / b', "b", true, 0, "b")
check_match('a / b / c', "a", true, 0, "a")
check_match('a / b / c', "b ", true, 1, "b")
check_match('{a / b / c}', "b ", true, 1, "b")
check_match('a / b / c', "c a", true, 2, "c")
check_match('(a / b / c)', "c a", true, 2, "c")
check_match('{a / b / c}', "c a", true, 2, "c")

check_match('{{a b} / b / {a c}}', "abK", true, 1)
check_match('{{a b} / b / {a c}}', "bJ", true, 1)
check_match('{{a b} / b / {a c}}', "acL", true, 1)

check_match('{{a b} / {b} / {a c}}', "bL", true, 1)
check_match('{{a b} / b / {a c}}', "bL", true, 1)
check_match('{a b} / b / {a c}', "bL", true, 1)

check_match('{{a b} / {b} / {a c}}', "bcL", true, 2)
check_match('{{a b} / (b ~) / {a c}}', "bcL", false)
check_match('{{a b} / (b ~) / {a c}}', "b.cL", true, 3)

----------------------------------------------------------------------------------------
heading("Cooked groups")
----------------------------------------------------------------------------------------
check_match('a b c', "a b c", true, 0, "a b c")
check_match('(a b c)', "a b c", true, 0, "a b c")
check_match('a (b c)', "a b c", true, 0, "a b c")
check_match('a / (b c)', "a b c", true, 4, "a")
check_match('a / (b c)', "b c a", true, 2, "b c")
check_match('a / (b c)', "b c", true, 0, "b c")
check_match('a / (b c)', " b c", false)
check_match('a / (b c)', "bc", false)

----------------------------------------------------------------------------------------
heading("Raw groups")
----------------------------------------------------------------------------------------
check_match('a b c', "abc", false)
check_match('{a b c}', "abc", true, 0, "abc")
check_match('a {b c}', "a bc", true, 0, "a bc")
check_match('a {b c}', "abc", false)
check_match('a {b c}', "a b", false)
check_match('{a b} c', "ab \tc", true, 0, "ab \tc")
check_match('{a b} c', "abc", false)
check_match('{a b} c', "a b", false)
check_match('{a b} c', "ab c", true, 0, "ab c")
check_match('a / {b c}', "a b c", true, 4, "a")
check_match('a / {b c}', "b c a", false)
check_match('a / {b c}', "b c", false)
check_match('a / {b c}', " bc", false)
check_match('a / {b c}', "bc", true, 0, "bc")
check_match('{a / b} c', "a b c", false)
check_match('{a / b} c', "b c a", true, 2, "b c")
check_match('{a / b} c', "b c", true, 0, "b c")
check_match('{a / b} c', " bc", false)

----------------------------------------------------------------------------------------
heading("Look-ahead")
----------------------------------------------------------------------------------------
check_match('>a', "x", false)
check_match('>a', "a", true, 1, "")
check_match('>a', "ayz", true, 3, "")		    -- ???
check_match('>{a}', "ayz", true, 3, "")
check_match('>(a)', "ayz", true, 3, "")		    -- ???
check_match('(>a)', "ayz", true, 3, "")
check_match('(>{a})', "ayz", true, 3, "")
check_match('(>(a))', "ayz", true, 3, "")

check_match('>a', "xyz", false)
check_match('(>a)', "xyz", false, 4, "")
check_match('{>a}', "axyz", true, 4, "")
check_match('{>a}', "xyz", false, 4, "")
check_match('>(a)', "axyz", true, 4, "")	    -- ???
check_match('(>(a))', "axyz", true, 4, "")	    -- ???
check_match('>{a ~}', "a.xyz", true, 5, "")
check_match('(>(a ~))', "a.xyz", true, 5, "")	    -- ???

----------------------------------------------------------------------------------------
heading("Negative look-ahead")
----------------------------------------------------------------------------------------
check_match('!a', "a", false)
check_match('!a', "x", true, 1, "")
check_match('!a', "xyz", true, 3, "")
check_match('!{a}', "xyz", true, 3, "")
check_match('!(a)', "xyz", true, 3, "")
check_match('(!a)', "xyz", true, 3, "")
check_match('(!{a})', "xyz", true, 3, "")
check_match('(!(a))', "xyz", true, 3, "")

check_match('!a', "axyz", false)
check_match('(!a)', "axyz", false, 4, "")
check_match('{!a}', "axyz", false, 4, "")
check_match('!(a)', "axyz", false, 4, "")	    -- ???
check_match('(!(a))', "axyz", false, 4, "")	    -- ???
check_match('!{a ~}', "axyz", true, 4, "")
check_match('!(a ~)', "axyz", true, 4, "")	    -- ???



----------------------------------------------------------------------------------------
heading("Precedence and right association")
----------------------------------------------------------------------------------------

-- Precedence/associativity examples
-- 
--    a / b c      ==  a / (b c)   
--    a b / c d    ==  a (b / (c d))
--    ! a b c      ==  (!a) b c
--    a b c *      ==  a b (c*)
--    ! a *        ==  !(a*)

subheading("Testing a / b c, which is equivalent to a / (b c)")
check_match('a / b c', 'a', true, 0, "a")
check_match('a / b c', 'ac', true, 1)

check_match('a / b c', 'a c', true, 2, "a")
-- Warning: did not match entire input line
check_match('a / b c', 'bc', false)

check_match('a / b c', 'b c', true, 0, "b c")
check_match('a / b c', 'b cx', true, 1, "b c")

subheading("Testing a b / c d, which is equivalent to a (b / (c d))")
check_match('a b / c d', 'a b', true, 0, "a b")
-- [test: [1: a b, 2: [a: [1: a]], 3: [b: [1: b]]]]
check_match('a b / c d', 'a b d', true, 2, "a b")
-- Warning: did not match entire input line
check_match('a b / c d', 'a c d', true, 0, "a c d")

subheading("Testing ! a b c, which is equivalent to !a (b c)")
check_match('! a b c', 'a b c', false)
check_match('! a b c', 'x', false)
check_match('! a b c', 'x b c', false)
check_match('! a b c', 'b c', true, 0, "b c")

subheading("Testing a b c*, which is equivalent to (a b c*)")
check_match('a b c*', 'a b c', true, 0, "a b c")
check_match('a b c*', 'a b c a b c', true, 6, "a b c")
check_match('a b c*', 'a b c c c', true, 4, "a b c")
check_match('a b c*', 'a b ccc', true, 0, "a b ccc")
check_match('a b c*', 'a b cccx', true, 1, "a b ccc")
check_match('a b c*', 'a b x', true, 1, "a b ")

subheading("Testing a b (c)*, for contrast with a b c*")
-- Note that c* is raw whereas (c)* is cooked
check_match('a b (c)*', 'a b ccc', true, 2, "a b c")
check_match('(a b (c)*)', 'a b ccc', true, 2, "a b c")
check_match('{(a b (c)*)}', 'a b ccc', true, 2, "a b c")
check_match('a b (c)*', 'a b c c c', true, 0, "a b c c c")
check_match('(a b (c)*)', 'a b c c c', true, 0, "a b c c c")
check_match('(a b (c)*)', 'a b c c c x', true, 2, "a b c c c")
check_match('(a b (c)*)', 'a b c c cx', true, 1, "a b c c c")
check_match('(a b (c)*)~', 'a b c c cx', false)

subheading("Testing a* b, recalling that * implies raw")
check_match('a* b', 'a b', true, 0, "a b")
check_match('a* b', 'a a b', false)

check_match('a* b', 'aaa b', true, 0, "aaa b")
check_match('a* b', ' b', true, 0, " b")
check_match('a* b', 'b', true, 0, "b")		    -- boundary change Saturday, April 23, 2016

subheading("Testing (a)* b")
check_match('(a)* b', 'a b', true, 0, "a b")
check_match('(a)* b', 'aa b', false)
check_match('(a)* b', 'a a a b', true, 0, "a a a b")
check_match('(a)* b', ' b', true, 0, " b")
check_match('(a)* b', 'b', true, 0, "b")	    -- boundary change Saturday, April 23, 2016

subheading("Testing {(a)* b}")
check_match('{(a)* b}', 'a b', false)
check_match('{(a)* b}', 'ab', true)
check_match('{(a)* b}', 'a a a b', false)
check_match('{(a)* b}', 'a a ab', true, 0, "a a ab")
check_match('{(a)* b}', 'b', true, 0, "b")
check_match('{(a)* b}', ' b', false)

subheading("Testing {(a)* a? b}")
check_match('{(a)* a? b}', 'ab', true, 0, "ab")
check_match('{(a)* a? b}', 'a b', false)
check_match('{(a)* a? b}', 'a a a b', false)
check_match('{(a)* a? b}', 'a a ab', true, 0, "a a ab")
check_match('{(a)* a? b}', 'a a a ab', true, 0, "a a a ab")

subheading("Testing !a+, which is equivalent to !(a+) or !{a+}")
check_match('a+', ' b', false)
check_match('!a+', ' b', true, 2, "")
check_match('!a+~', ' b', true, 1, " ")
check_match('(!a+)', ' b', true, 2, "")
check_match('{!a+}', ' b', true, 2, "")
check_match('!a+', 'b', true, 1, "")
check_match('!a+', '', true, 0, "")
check_match('!a+', 'a', false)
check_match('(!a+)', 'a', false)
check_match('{!a+}', 'a', false)
check_match('!a+', 'ax', false)
check_match('(!a+)', 'ax', false)
check_match('{!a+}', 'ax', false)
check_match('!a+', 'a x', false)
check_match('(!a+)', 'a x', false)
check_match('{!a+}', 'a x', false)
check_match('!a+', 'aaa', false)

subheading("Testing a{1,2} against a, aa, aaa, and x")
check_match('a{1,2}', 'a', true, 0, "a")
check_match('a{1,2}', 'aa', true, 0, "aa")
check_match('a{1,2}~', 'aa', true, 0, "aa")
check_match('a{1,2}', 'aaa', true, 1, "aa")
check_match('a{1,2}~', 'aaa', false)
check_match('(a{1,2})', 'aaa', true, 1, "aa")
check_match('(a{1,2}~)', 'aaa', false)
check_match('{a{1,2}~}', 'aaa', false)
check_match('a{1,2}', 'x', false)

subheading("Testing a{0,1}~ against a, aa, and x")
check_match('a{0,1}', 'a', true, 0, "a")
check_match('a{0,1}', 'aa', true, 1, "a")
check_match('a{0,1}~', 'a', true, 0, "a")
check_match('a{0,1}~', 'aa', false)
check_match('(a{0,1}~)', 'aa', false)
check_match('{a{0,1}~}', 'aa', false)
check_match('a{0,1}~', 'x', true, 1, "")
check_match('(a){0,1}~', 'a', true, 0, "a")
check_match('(a){0,1}~', 'aa', false)
check_match('((a){0,1}~)', 'aa', false)
check_match('{(a){0,1}~}', 'aa', false)
check_match('{(a){0,1}}', 'aa', true, 1, "a")
check_match('(a){0,1}~', 'x', true, 1, "")

subheading("Confirming that a{0,1} is equivalent to a?")
check_match('(a{0,1})', '', true, 0, "")
check_match('(a?)', '', true, 0, "")
check_match('{a{0,1}}', '', true, 0, "")
check_match('{a?}', '', true, 0, "")
check_match('(a{0,1})', 'a', true, 0, "a")
check_match('(a?)', 'a', true, 0, "a")
check_match('(a{0,1})', 'a', true, 0, "a")
check_match('(a?)', 'a', true, 0, "a")
check_match('{a{0,1}}', 'aa', true, 1, "a")
check_match('{a?}', 'aa', true, 1, "a")

heading("Boundary testing")
subheading("Kleene star")
check_match('a*', 'aa', true, 0, "aa")
check_match('{a}*', 'aa', true, 0, "aa")
check_match('(a)*~', 'aa', false)
check_match('(a)*', 'aa', true, 1, "a")
check_match('{a}*', 'aax', true, 1)
check_match('{a}*~', 'aax', false)
check_match('{{a}*}', 'aa ', true, 1, "aa")
check_match('{(a)*}', 'aax', true, 2, "a")	    -- odd looking, but correct
check_match('(a)*', 'a a', true, 0, "a a")
check_match('(a)*', 'a ax', true, 1)
check_match('(a)*~', 'a ax', false)
check_match('(a)*', 'a a   ', true, 3, "a a")
check_match('((a)*)', 'a a   ', true, 3, "a a")
check_match('{(a)*}', 'a a   ', true, 3, "a a")
check_match('(a)*', ' a a   ', true, 7, "")
check_match('{(a)*}', ' a a   ', true, 7, "")

subheading("Explicit boundary pattern")
check_match('~(a)*', ' a a   ', true, 3, " a a")
check_match('(~(a)*)', ' a a   ', true, 3, " a a")
ok, msg = pcall(e.load, e, "token = { ![[:space:]] . {!~ .}* }")
check(ok)
check_match('token', 'The quick, brown fox.\nSentence fragment!!  ', true, 40, "The")
check_match('token token token', 'The quick, brown fox.\nSentence fragment!!  ', true, 33, "The quick,")
check_match('{(token token token)}', 'The quick, brown fox.\nSentence fragment!!  ', true, 33, "The quick,")
check_match('token{4,}', 'The quick, brown fox.\nSentence fragment!!', false)
check_match('(token){4,}', 'The quick, brown fox.\nSentence fragment!!', true, 0)
-- The 4th token is a comma in the following match:
check_match('(token){4,4}', 'The quick, brown fox.\nSentence fragment!!  ', true, 27)
check_match('token*', 'The quick, brown fox.\nSentence fragment!!  ', true, 40, "The")
check_match('{token}*', 'The quick, brown fox.\nSentence fragment!!  ', true, 40, "The")
check_match('({token}*)', 'The quick, brown fox.\nSentence fragment!!  ', true, 40, "The")
check_match('(token)*', 'The quick, brown fox.\nSentence fragment!!  ', true, 2)
check_match('((token)*)', 'The quick, brown fox.\nSentence fragment!!  ', true, 2)
check_match('{(token)*}', 'The quick, brown fox.\nSentence fragment!!  ', true, 2)

check_match('(token)*', '\tThe quick, brown fox.\nSentence fragment!!  ', true, 44, "")
check_match('{(token)*}', '\tThe quick, brown fox.\nSentence fragment!!  ', true, 44, "")
check_match('~(token)*', '\tThe quick, brown fox.\nSentence fragment!!  ', true, 2)
check_match('(~ token)*', '\tThe quick, brown fox.\nSentence fragment!!  ', true, 2)
check_match('(~ token ~)*', '\tThe quick, brown fox.\nSentence fragment!!  ', true, 0)
check_match('{~ token ~}*', '\tThe quick, brown fox.\nSentence fragment!!  ', true, 0)

subheading("Boundary idempotence")
check_match('~~~~~~', '     V', true, 1, "     ")
check_match('~~~~~~', 'V', true, 1, "")		    -- idempotent boundary
check_match('(~~~~~~)', '     V', true, 1, "     ")
check_match('(~~~~~~)', 'V', true, 1, "")	    -- idempotent boundary
check_match('{~~~~~~}', '     V', true, 1, "     ")
check_match('{~~~~~~}', 'V', true, 1, "")	    -- idempotent boundary

check_match('~', 'X', true, 1, "")
check_match('~', '', true, 0, "")
check_match('"X"~', 'X', true, 0, "X")
check_match('"X"~~~~', 'X', true, 0, "X")	    -- idempotent boundary

subheading("Alternation (basic)")
check_match('{ a / b }', 'ax', true, 1, "a")
check_match('a / b', 'ax', true, 1)
check_match('a / b', 'a x', true, 2)
check_match('a / b', 'a', true)
check_match('(a / b)', 'ax', true, 1)
check_match('(a / b)', 'a x', true, 2, "a")
check_match('{a / b}', 'a x', true, 2, "a")
check_match('{{a / b}}', 'a x', true, 2, "a")
check_match('{(a / b)}', 'a x', true, 2, "a")
check_match('(a / b)', 'a', true)
check_match('{a / b}', 'a', true)
check_match('a / b', 'a', true)

subheading("Alternation and sequence")
check_match('b a / b', 'b', false)
check_match('b a / b', 'b a', true)
check_match('b a / b', 'b b', true)
check_match('b a / b', 'b a   x', true, 4)

check_match('b (a / b)', 'b', false)
check_match('b (a / b)', 'b a', true)
check_match('b (a / b)', 'b b', true)
check_match('b (a / b)', 'b a   x', true, 4)

check_match('b {a / b}', 'b', false)
check_match('b {a / b}', 'b a', true)
check_match('b {a / b}', 'b b', true)
check_match('b {a / b}', 'b a   x', true, 4)

check_match('(b a / b)', 'b', false)
check_match('(b a / b)', 'b a', true)
check_match('(b a / b)', 'b b', true)
check_match('(b a / b)', 'b a   x', true, 4)

subheading("Key tests for sequences/alternates")
-- The tests above are just for consistency.  Here's the important stuff:
check_match('{b a / b}', 'b', false)
check_match('{b a / b}', 'b a', false)
check_match('{b a / b}', 'ba', true)
check_match('{b a / b}', 'bb', true)
check_match('{b a / b}', 'b a   x', false)
check_match('{b a / b}', 'ba   x', true, 4)
check_match('{b a / b}', 'bax', true, 1)

check_match('{b (a / b)}', 'b', false)
check_match('{b (a / b)}', 'b a', false)
check_match('{b (a / b)}', 'ba', true)
check_match('{b (a / b)}', 'bb', true)
check_match('{b (a / b)}', 'b a   x', false)
check_match('{b (a / b)}', 'ba   x', true, 4)

check_match('{b (a / b)}', 'bax', true, 1)
check_match('{b {a / b}}', 'bax', true, 1)
check_match('({b {a / b}})', 'bax', true, 1)
check_match('({b {a / b}}~)', 'bax', false)
check_match('({b {a / b}})', 'ba xyz', true, 4)
check_match('({b (a / b)})', 'bax', true, 1)
check_match('(b (a / b))', 'bax', false)
check_match('(b (a / b))', 'b a x', true, 2)
check_match('(b (a / b))', 'b b', true, 0)

check_match('{b (a)}', 'bax', true, 1)
check_match('({b (a)})', 'bax', true, 1)
check_match('({b (a)}~)', 'bax', false)
check_match('{b (a)}', 'ba x', true, 2)

----------------------------------------------------------------------------------------
heading("Quantified expressions")
----------------------------------------------------------------------------------------
subheading("Kleene star")
check_match('a*', '', true)
check_match('a*', 'a', true)
check_match('a*', 'aaaaaa', true)
check_match('a*', 'aaaaaa ', true, 1)
check_match('{a*}', 'aaaaaa ', true, 1)		    -- let's not capture the trailing boundary
check_match('a*', 'x', true, 1, '')
check_match('{a}*', '', true)
check_match('{a}*', 'a', true)
check_match('{a}*', 'aaaaaa', true)
check_match('{a}*', 'aaaaaa ', true, 1)
check_match('{{a}*}', 'aaaaaa ', true, 1)
check_match('{a}*', 'x', true, 1, '')
check_match('(a)*', '', true)
check_match('(a)*', 'a', true)
check_match('(a)*', 'aa', true, 1)
check_match('(a)*', 'a a a a', true)
check_match('(a)*', 'a a a a    ', true, 4)
check_match('((a)*)', 'a a a a    ', true, 4)
check_match('{(a)*}', 'a a a a    ', true, 4)	    -- 4 spaces leftover
check_match('(a)*', 'a a a a x', true, 2)
check_match('((a)*)', 'a a a a x', true, 2)
check_match('{(a)*}', 'a a a a x', true, 2)
check_match('(a)*', 'x', true, 1, '')

subheading("Plus")
check_match('a+', '', false)
check_match('a+', 'a', true)
check_match('a+', 'aaaaaa', true)
check_match('a+', 'aaaaaa ', true, 1)
check_match('{a+}', 'aaaaaa ', true, 1)
check_match('a+', 'x ', false)
check_match('{a}+', '', false)
check_match('{a}+', 'a', true)
check_match('{a}+', 'aaaaaa', true)
check_match('{a}+', 'aaaaaa ', true, 1)
check_match('{{a}+}', 'aaaaaa ', true, 1)
check_match('{a}+', 'x ', false)
check_match('(a)+', '', false)
check_match('(a)+', 'a', true)
check_match('(a)+', 'aa', true, 1)
check_match('(a)+', 'a a a a', true)
check_match('(a)+', 'a a a a    ', true, 4)	    -- 4 spaces left over
check_match('(a)+', 'a a a a x', true, 2)
check_match('(a)+', 'x', false)

subheading("Question")
check_match('a?', '', true, 0, '')
check_match('a?', 'a', true, 0, 'a')
check_match('a?', 'aaaaaa', true, 5)
check_match('a?~', 'aaaaaa', false)
check_match('a?', 'a ', true, 1, 'a')
check_match('{a}?', '', true, 0, '')
check_match('{a}?', 'a', true, 0, 'a')
check_match('{a}?', 'aaaaaa', true, 5)
check_match('{a}?~', 'aaaaaa', false)
check_match('{{a}?}', 'aaaaaa', true, 5, 'a')
check_match('{a}?', 'a ', true, 1, 'a')
check_match('(a)?', '', true, 0, '')
check_match('(a)?', 'a', true, 0, 'a')
check_match('(a)?', 'aa', true, 1, 'a')
check_match('(a)?~', 'aa', false)
check_match('((a)?)', 'aa', true, 1)
check_match('((a)? ~)', 'aa', false)
check_match('{(a)?}', 'aa', true, 1, 'a')
check_match('(a)?', 'a a', true, 2, 'a')
check_match('((a)?)', 'a a', true, 2, 'a')
check_match('{(a)?}', 'a a', true, 2, 'a')
check_match('(a)?', 'ax', true, 1)
check_match('(a)?~', 'ax', false)
check_match('((a)?)', 'ax', true, 1)
check_match('((a)? ~)', 'ax', false)
check_match('{(a)?}', 'ax', true, 1, 'a')
check_match('(a)?', 'x', true, 1, '')
check_match('((a)?)', 'x', true, 1, '')
check_match('{(a)?}', 'x', true, 1, '')

subheading("Range with min (cooked)")
check_match('c{0,}', '', true)
check_match('c{0,}', 'x', true, 1)		    -- because start of input is a boundary
check_match('c{0,}', 'c', true)
check_match('c{0,}', 'cx', true, 1)
check_match('c{0,}~', 'cx', false)
check_match('c{0,}', 'c x', true, 2)
check_match('c{0,}', ' x', true, 2)
check_match('c{0,}', '!', true, 1)
check_match('c{0,}', 'cccccccccc x', true, 2)

check_match('c{1,}', '', false)
check_match('c{1,}', 'x', false)
check_match('c{1,}', 'c', true)
check_match('c{1,}', 'cx', true, 1)
check_match('c{1,}~', 'cx', false)
check_match('c{1,}', 'c x', true, 2)
check_match('c{1,}', ' x', false)
check_match('c{1,}', 'c!', true, 1)
check_match('c{1,}', 'cccccccccc#x', true, 2)

check_match('c{2,}', '', false)
check_match('c{2,}', 'x', false)
check_match('c{2,}', 'c', false)
check_match('c{2,}', 'ccx', true, 1)
check_match('c{2,}~', 'ccx', false)
check_match('c{2,}', 'cc x', true, 2)
check_match('c{2,}', ' x', false)
check_match('c{2,}', 'cc!', true, 1)
check_match('c{2,}', 'cccccccccc#x', true, 2)

subheading("Range with min (raw)")
check_match('{c{0,}}', '', true)
check_match('{c{0,}}', 'x', true, 1)		    -- because start of input is a boundary
check_match('{c{0,}}', 'c', true)
check_match('{c{0,}}', 'cx', true, 1)
check_match('{c{0,}}', 'c x', true, 2)
check_match('{c{0,}}', ' x', true, 2)
check_match('{c{0,}}', '!', true, 1)
check_match('{c{0,}}', 'cccccccccc x', true, 2)

check_match('{c{1,}}', '', false)
check_match('{c{1,}}', 'x', false)
check_match('{c{1,}}', 'c', true)
check_match('{c{1,}}', 'cx', true, 1)
check_match('{c{1,}}', 'c x', true, 2)
check_match('{c{1,}}', ' x', false)
check_match('{c{1,}}', 'c!', true, 1)
check_match('{c{1,}}', 'cccccccccc#x', true, 2)

check_match('{c{2,}}', '', false)
check_match('{c{2,}}', 'x', false)
check_match('{c{2,}}', 'c', false)
check_match('{c{2,}}', 'ccx', true, 1)
check_match('{c{2,}}', 'cc x', true, 2)
check_match('{c{2,}}', ' x', false)
check_match('{c{2,}}', 'cc!', true, 1)
check_match('{c{2,}}', 'cccccccccc#x', true, 2)

subheading("Range with max (cooked)")
-- check_match('c{,0}', '', true)
-- check_match('c{,0}', 'x', true, 1)		    -- because start of input is a boundary
-- check_match('c{,0}', 'c', true)
-- check_match('c{,0}', 'cx', true, 1)
-- check_match('c{,0}~', 'cx', false)
-- check_match('c{,0}', 'c x', true, 2)
-- check_match('c{,0}', ' x', true, 2)
-- check_match('c{,0}', '!', true, 1)
-- check_match('c{,0}', 'cccccccccc x', true, 2)

check_match('c{,1}', '', true)
check_match('c{,1}', 'x', true, 1)
check_match('c{,1}', 'c', true)
check_match('c{,1}', 'cx', true, 1)
check_match('c{,1}~', 'cx', false)
check_match('c{,1}', 'c x', true, 2)
check_match('c{,1}', ' x', true, 2)
check_match('c{,1}', 'c!', true, 1)
check_match('c{,1}', 'cccccccccc#x', true, 11)
check_match('c{,1}~', 'cccccccccc#x', false)
check_match('(c){,1}', 'cccccccccc#x', true, 11)
check_match('(c){,1}~', 'cccccccccc#x', false)

check_match('c{,2}', '', true)
check_match('c{,2}', 'x', true, 1)
check_match('c{,2}', 'c', true)
check_match('c{,2}', 'ccx', true, 1)
check_match('(c){,2}', 'ccx', true, 2)
check_match('c{,2}~', 'ccx', false)
check_match('c{,2}', 'cc x', true, 2)
check_match('c{,2}', ' x', true, 2)
check_match('c{,2}', 'cc!', true, 1)
check_match('c{,2}', 'cccccccccc#x', true, 10)
check_match('c{,2}~', 'cccccccccc#x', false)
check_match('(c){,2}', 'cccccccccc#x', true, 11)
check_match('(c){,2}~', 'cccccccccc#x', false)

subheading("Range with max (raw)")
-- check_match('{c{,0}}', '', true)
-- check_match('{c{,0}}', 'x', true, 1)		    because start of input is a boundary
-- check_match('{c{,0}}', 'c', true)
-- check_match('{c{,0}}', 'cx', true, 1)
-- check_match('{c{,0}}', 'c x', true, 2)
-- check_match('{c{,0}}', ' x', true, 2)
-- check_match('{c{,0}}', '!', true, 1)
-- check_match('{c{,0}}', 'cccccccccc x', true, 2)

check_match('{c{,1}}', '', true)
check_match('{c{,1}}', 'x', true, 1)
check_match('{c{,1}}', 'c', true)
check_match('{c{,1}}', 'cx', true, 1)
check_match('{c{,1}}', 'c x', true, 2)
check_match('{c{,1}}', ' x', true, 2)
check_match('{c{,1}}', 'c!', true, 1)
check_match('{c{,1}}', 'cccccccccc#x', true, 11)

check_match('{c{,2}}', '', true)
check_match('{c{,2}}', 'x', true, 1)
check_match('{c{,2}}', 'c', true)
check_match('{c{,2}}', 'ccx', true, 1)
check_match('{c{,2}}', 'cc x', true, 2)
check_match('{c{,2}}', ' x', true, 2)
check_match('{c{,2}}', 'cc!', true, 1)
check_match('{c{,2}}', 'cccccccccc#x', true, 10)

subheading("Range with min, max (misc)")
check_match('a{3,5}', '', false)
check_match('a{3,5}', 'aa', false)
check_match('a{3,5}', 'aaa', true)
check_match('a{3,5}', 'aaaa', true)
check_match('a{3,5}', 'aaaaa', true)
check_match('a{3,5}', 'aaaaaa', true, 1)
check_match('a{3,5}~', 'aaaaaa', false)
check_match('(a{3,5})', 'aaaaaa', true, 1)
check_match('(a{3,5} ~)', 'aaaaaa', false)
check_match('{a{3,5}}', 'aaaaaa', true, 1)
check_match('a{3,5}', 'a a a', false)
check_match('(a){3,5}', 'a a a', true)
check_match('((a)){3,5}', 'a a a', true)
check_match('({((a))}){3,5}', 'a a a a ', true, 1)

check_match('{((a))}{3,5}', 'a a a', false)
check_match('{((a))}{3,5}', 'aaa', true)
check_match('{((a))}{3,5}', 'aaax', true, 1)	    -- N.B.
check_match('{((a))}{3,5}~', 'aaax', false)
check_match('{ {((a))}{3,5} }', 'aaax', true, 1)    -- N.B.

check_match('a{3,5}', 'a a a', false)
check_match('a{3,5}', 'aaa', true)
check_match('a{3,5}', 'aaax', true, 1)	    -- N.B.
check_match('a{3,5}~', 'aaax', false)
check_match('a{3,5}', 'aaax', true, 1)    -- N.B.

check_match('{a}{3,5}', 'a a a', false)
check_match('{a}{3,5}', 'aaa', true)
check_match('{a}{3,5}', 'aaax', true, 1)	    -- N.B.
check_match('{a}{3,5}~', 'aaax', false)
check_match('{a}{3,5}', 'aaax', true, 1)    -- N.B.


subheading("Range with min, max (cooked)")
check_match('b{2,4}', '', false)
check_match('b{2,4}', 'x', false)
check_match('b{2,4}', 'b', false)
check_match('b{2,4}', 'bb', true)
check_match('b{2,4}', 'bbb', true)
check_match('b{2,4}', 'bbbb', true)

-- cooked mode, so looking for a boundary after the b's
check_match('b{2,4}', 'bbbbb', true, 1)
check_match('b{2,4}~', 'bbbbb', false)
check_match('b{2,4}', 'bbxyz', true, 3)
check_match('b{2,4}~', 'bbxyz', false)
check_match('b{2,4}', 'bbbxyz', true, 3)
check_match('b{2,4}~', 'bbbxyz', false)
check_match('b{2,4}', 'bbbbxyz', true, 3)
check_match('b{2,4}~', 'bbbbxyz', false)
check_match('b{2,4}', 'bbbbbxyz', true, 4)
check_match('b{2,4}~', 'bbbbbxyz', false)
check_match('b{2,4}', 'b b', false)
check_match('b{2,4}', 'bb b', true, 2, 'bb')
check_match('b{2,4}', 'bbb b', true, 2, 'bbb')
check_match('b{2,4}', 'bbbb b', true, 2, 'bbbb')

subheading("Range with min, max (raw)")
check_match('{b{2,4}}', 'bbbbb', true, 1)
check_match('{b{2,4}}', 'bbxyz', true, 3)
check_match('{b{2,4}}', 'bbbxyz', true, 3)
check_match('{b{2,4}}', 'bbbbxyz', true, 3)
check_match('{b{2,4}}', 'bbbbbxyz', true, 4)
check_match('{b{2,4}}', 'b b', false)
check_match('{b{2,4}}', 'bb b', true, 2, 'bb')
check_match('{b{2,4}}', 'bbb b', true, 2, 'bbb')
check_match('{b{2,4}}', 'bbbb b', true, 2, 'bbbb')

subheading("Sequences of raw and cooked groups")
check_match('{a b} {c d}', 'ab cd', true)
check_match('{{a b} {c d}}', 'abcd', true)
check_match('({a b} {c d})', 'ab cd', true)
check_match('({{a b} {c d}})', 'abcd', true)

check_match('(a b) (c d)', 'a b c d', true)
check_match('(a b) (c d)', 'a bc d', false)
check_match('{(a b) (c d)}', 'a bc d', true)

check_match('((a b) (c d))', 'a b c d', true)
check_match('((a b) (c d))', 'a bc d', false)
check_match('({(a b) (c d)})', 'a bc d', true)
check_match('({(a b) (c d)})', 'a b c d', false)

check_match('({(a b) (c d)})', 'a bc dx', true, 1)
check_match('({(a b) (c d)} ~)', 'a bc dx', false)
check_match('{(a b) (c d)} ~', 'a bc dx', false)
check_match('((a b) (c d))', 'a b c dx', true, 1)
check_match('((a b) (c d) ~)', 'a b c dx', false)
check_match('(a b) (c d)', 'a b c dx', true, 1)
check_match('(a b) (c d) ~', 'a b c dx', false)
check_match('{a b} {c d}', 'ab cdx', true, 1)
check_match('{a b} {c d} ~', 'ab cdx', false)

subheading("Multiply-nested groups")
check_match('{a b}', 'abx', true, 1)
check_match('{{a b}}', 'abx', true, 1)
check_match('{{{a b}}}', 'abx', true, 1)
check_match('({a b})', 'abx', true, 1)
check_match('{a b}~', 'abx', false)
check_match('({a b}~)', 'abx', false)
check_match('(a b)', 'a b', true)
check_match('((a b))', 'a b', true)
check_match('(((a b)))', 'a b', true)
check_match('{(((a b)))}', 'a bx', true, 1)
check_match('{{(((a b)))}}', 'a bx', true, 1)
check_match('({{(((a b)))}})', 'a bx', true, 1)
check_match('({{(((a b ~)))}}~)', 'a bx', false)
check_match('({{(((a b)))}})', 'a b ', true, 1)


heading("Quantified alternatives and sequences")
subheading("Cooked alternatives with question operator")
check_match('(a/b/c)?', '', true)
check_match('(a/b/c)?', 'a', true)
check_match('(a/b/c)?', 'b', true)
check_match('(a/b/c)?', 'c', true)
check_match('(a/b/c)?', 'ab', true, 1)
check_match('(a/b/c)?', 'a!', true, 1)
-- next set same as previous set
check_match('{a/b/c}?', '', true)
check_match('{a/b/c}?', 'a', true)
check_match('{a/b/c}?', 'b', true)
check_match('{a/b/c}?', 'c', true)
check_match('{a/b/c}?', 'ab', true, 1)
check_match('{a/b/c}? ~', 'ab', false)
check_match('{a/b/c}?', 'a!', true, 1)
-- next set same as previous set
check_match('({a/b/c}?)', '', true)
check_match('({a/b/c}?)', 'a', true)
check_match('({a/b/c}?)', 'b', true)
check_match('({a/b/c}?)', 'c', true)
check_match('({a/b/c}?)', 'ab', true, 1)
check_match('({a/b/c}? ~)', 'ab', false)
check_match('({a/b/c}?)', 'a!', true, 1)
-- and this one is different
check_match('{{a/b/c}?}', '', true)
check_match('{{a/b/c}?}', 'a', true)
check_match('{{a/b/c}?}', 'b', true)
check_match('{{a/b/c}?}', 'c', true)
check_match('{{a/b/c}?}', 'ab', true, 1)	    -- the difference
check_match('{{a/b/c}?}', 'a!', true, 1)

check_match('{a/b/c}? d', 'a d', true)
check_match('{a/b/c}? d', 'ad', false)
check_match('({a/b/c}? d)', 'a d', true)
check_match('({a/b/c}? d)', 'ad', false)
check_match('{{a/b/c}? d}', 'a d', false)
check_match('{{a/b/c}? d}', 'ad', true)

subheading("Alternatives with range operator")
check_match('(a/b/c){1,2}', '', false)
check_match('(a/b/c){1,2}', 'a', true)
check_match('(a/b/c){1,2}', 'b', true)
check_match('(a/b/c){1,2}', 'c', true)
check_match('(a/b/c){1,2}', 'a b', true)
check_match('(a/b/c){1,2}', 'c c', true)
check_match('(a/b/c){1,2}', 'c a', true)
check_match('(a/b/c){1,2}', 'c a ', true, 1)
check_match('(a/b/c){1,2}', 'a c!', true, 1, "a c")
check_match('(a/b/c){1,2}', 'a cX', true, 1, "a c")
-- next set same as previous set
check_match('((a/b/c){1,2})', '', false)
check_match('((a/b/c){1,2})', 'a', true)
check_match('((a/b/c){1,2})', 'b', true)
check_match('((a/b/c){1,2})', 'c', true)
check_match('((a/b/c){1,2})', 'a b', true)
check_match('((a/b/c){1,2})', 'c c', true)
check_match('((a/b/c){1,2})', 'c a', true)
check_match('((a/b/c){1,2})', 'c a ', true, 1)
check_match('((a/b/c){1,2})', 'a c!', true, 1, "a c")
check_match('((a/b/c){1,2})', 'a cX', true, 1, "a c")
-- difference
check_match('{(a/b/c){1,2}}', '', false)
check_match('{(a/b/c){1,2}}', 'a', true)
check_match('{(a/b/c){1,2}}', 'b', true)
check_match('{(a/b/c){1,2}}', 'c', true)
check_match('{(a/b/c){1,2}}', 'a b', true)
check_match('{(a/b/c){1,2}}', 'c c', true)
check_match('{(a/b/c){1,2}}', 'c a', true)
check_match('{(a/b/c){1,2}}', 'c a ', true, 1)
check_match('{(a/b/c){1,2}}', 'a c!', true, 1)
check_match('{(a/b/c){1,2}}', 'a cX', true, 1)

subheading("Raw alternatives with question operator")
check_match('{a/b/c}{1,2}', '', false)
check_match('{a/b/c}{1,2}', 'a', true)
check_match('{a/b/c}{1,2}', 'b', true)
check_match('{a/b/c}{1,2}', 'c', true)
check_match('{a/b/c}{1,2}', 'ab', true)
check_match('{a/b/c}{1,2}', 'cc', true)
check_match('{a/b/c}{1,2}', 'ca', true)
check_match('{a/b/c}{1,2}', 'ca ', true, 1)
check_match('{a/b/c}{1,2}', 'ac!', true, 1)
check_match('{a/b/c}{1,2}', 'acX', true, 1)
check_match('{a/b/c}{1,2}~', 'acX', false)
-- same results as previous set
check_match('({a/b/c}{1,2})', '', false)
check_match('({a/b/c}{1,2})', 'a', true)
check_match('({a/b/c}{1,2})', 'b', true)
check_match('({a/b/c}{1,2})', 'c', true)
check_match('({a/b/c}{1,2})', 'ab', true)
check_match('({a/b/c}{1,2})', 'cc', true)
check_match('({a/b/c}{1,2})', 'ca', true)
check_match('({a/b/c}{1,2})', 'ca ', true, 1)
check_match('({a/b/c}{1,2})', 'ac!', true, 1)
check_match('({a/b/c}{1,2})', 'acX', true, 1)
check_match('({a/b/c}{1,2}~)', 'acX', false)
-- same results as previous set
check_match('{{a/b/c}{1,2}}', '', false)
check_match('{{a/b/c}{1,2}}', 'a', true)
check_match('{{a/b/c}{1,2}}', 'b', true)
check_match('{{a/b/c}{1,2}}', 'c', true)
check_match('{{a/b/c}{1,2}}', 'ab', true)
check_match('{{a/b/c}{1,2}}', 'cc', true)
check_match('{{a/b/c}{1,2}}', 'ca', true)
check_match('{{a/b/c}{1,2}}', 'ca ', true, 1)
check_match('{{a/b/c}{1,2}}', 'ac!', true, 1)
check_match('{{a/b/c}{1,2}}', 'acX', true, 1)
check_match('{{a/b/c}{1,2}}~', 'acX', false)

subheading("Sequences with question operator")
check_match('(a b)?', '', true)
check_match('(a b)?', 'a', true, 1)
check_match('(a b)?', 'ab', true, 2)
check_match('(a b)?', 'a b', true)
check_match('(a b)?', 'a b  ', true, 2)
check_match('((a b))?', 'a b  ', true, 2)
check_match('(a b)?', 'a bx  ', true, 3)
check_match('(a b)?~', 'a bx  ', false)
-- same results as previous set
check_match('((a b)?)', '', true)
check_match('((a b)?)', 'a', true, 1)
check_match('((a b)?)', 'ab', true, 2)
check_match('((a b)?)', 'a b', true)
check_match('((a b)?)', 'a b  ', true, 2)
check_match('((a b)?)', 'a bx  ', true, 3)
check_match('((a b)?~)', 'a bx  ', false)
-- same results as previous set
check_match('{(a b)?}', '', true)
check_match('{(a b)?}', 'a', true, 1)
check_match('{(a b)?}', 'ab', true, 2)
check_match('{(a b)?}', 'a b', true)
check_match('{(a b)?}', 'a b  ', true, 2)
check_match('{(a b)?}', 'a bx  ', true, 3)
check_match('{(a b)? ~}', 'a bx  ', false)

subheading("Cooked sequences with range operator")
check_match('(a b){2,2}', 'a b', false)
check_match('(a b){2,2}', 'a b a b', true)
check_match('(a b){2,2}', 'a ba b', false)
check_match('(a b){2,2}', 'a b a b ', true, 1)
check_match('(a b){2,2}', 'a b a bx', true, 1)
check_match('(a b){2,2}~', 'a b a bx', false)
-- same results as previous set
check_match('((a b){2,2})', 'a b', false)
check_match('((a b){2,2})', 'a b a b', true)
check_match('((a b){2,2})', 'a ba b', false)
check_match('((a b){2,2})', 'a b a b ', true, 1)
check_match('((a b){2,2})', 'a b a bx', true, 1)
check_match('((a b){2,2} ~)', 'a b a bx', false)
-- same results as previous set
check_match('{(a b){2,2}}', 'a b', false)
check_match('{(a b){2,2}}', 'a b a b', true)
check_match('{(a b){2,2}}', 'a ba b', false)
check_match('{(a b){2,2}}', 'a b a b ', true, 1)
check_match('{(a b){2,2}}', 'a b a bx', true, 1)
check_match('{(a b){2,2} ~}', 'a b a bx', false)

subheading("Raw sequences with range operator")
check_match('{a b}{2,2}', 'ab', false)
check_match('{a b}{2,2}', 'abab', true)
check_match('{a b}{2,2}', 'ab ab', false)
check_match('{a b}{2,2}', 'abab!', true, 1)
check_match('{a b}{2,2}', 'ababx', true, 1)
check_match('{a b}{2,2}~', 'ababx', false)
check_match('{a b}{2,2}', 'abab ', true, 1)
-- same results as previous set
check_match('({a b}{2,2})', 'ab', false)
check_match('({a b}{2,2})', 'abab', true)
check_match('({a b}{2,2})', 'ab ab', false)
check_match('({a b}{2,2})', 'abab!', true, 1)
check_match('({a b}{2,2})', 'ababx', true, 1)
check_match('({a b}{2,2} ~)', 'ababx', false)
check_match('({a b}{2,2})', 'abab ', true, 1)
-- difference
check_match('{{a b}{2,2}}', 'ab', false)
check_match('{{a b}{2,2}}', 'abab', true)
check_match('{{a b}{2,2}}', 'ab ab', false)
check_match('{{a b}{2,2}}', 'abab!', true, 1)
check_match('{{a b}{2,2}}', 'ababx', true, 1)
check_match('{{a b}{2,2} ~}', 'ababx', false)
check_match('{{a b}{2,2}}', 'abab ', true, 1)

heading("Character sets")

subheading("Rejecting illegal expressions")
for _, exp in ipairs{"[]]",
--		     "[^]",
--		     "[xyz^]",
		     "[[abc] / [def]]",
		     "[[a-z] misplaced_identifier [def]]",
		     "[[a-z] [def]",		    -- no final closing bracket
		     "[]",			    -- this was legal before v0.99?
                     "[[abc][]]"} do
   pat, msg = e:compile(exp)
   check(not pat, "this expression was expected to fail: " .. exp)
   if (type(msg)=="table" and msg[1]) then
      check(violation.syntax.is(msg[1]))
   end
   -- :find("Syntax error at line 1"), "Did not get syntax error for exp " ..
   -- exp .. ".  Message was: " .. msg .. '\n')
end
success, msg = e:compile("[:foobar:]")
check(not success)
check(type(msg)=="table" and msg[1])
check(violation.compile.is(msg[1])) -- .message:find("named charset not defined"))

subheading("Named character sets")

function test_charsets(exp, true_inputs, false_inputs)
   map(function(input) return check_match(exp, input, true, nil, nil, 2); end, true_inputs)
   map(function(input) return check_match(exp, input, false, nil, nil, 2); end, false_inputs)
end


test_charsets("[[:print:]]", {"a", "1", "#", " "}, {"\t", "\b"})
test_charsets("[:print:]", {"a", "1", "#", " "}, {"\t", "\b"})
test_charsets("[[:graph:]]", {"a", "1", "#"}, {" ", "\t", "\b"})
test_charsets("[:graph:]", {"a", "1", "#"}, {" ", "\t", "\b"})
test_charsets("[[:upper:]]", {"A", "Q"}, {"a", "q", " ", "!", "0", "\b"})
test_charsets("[:upper:]", {"A", "Q"}, {"a", "q", " ", "!", "0", "\b"})
test_charsets("[[:lower:]]", {"a", "m"}, {"A", "M", "!", "0", " "})
test_charsets("[:lower:]", {"a", "m"}, {"A", "M", "!", "0", " "})
test_charsets("[[:alpha:]]", {"A", "z"}, {" ", "!", "0", "\\b"})
test_charsets("[:alpha:]", {"A", "z"}, {" ", "!", "0", "\\b"})
test_charsets("[[:alnum:]]", {"A", "0", "e"}, {" ", "!", "\\b"})
test_charsets("[:alnum:]", {"A", "0", "e"}, {" ", "!", "\\b"})
test_charsets("[[:digit:]]", {"0", "9"}, {"a", " ", "!"})
test_charsets("[:digit:]", {"0", "9"}, {"a", " ", "!"})
test_charsets("[[:xdigit:]]", {"a", "A", "f", "F", "1", "9"}, {"g", " ", "!"})
test_charsets("[:xdigit:]", {"a", "A", "f", "F", "1", "9"}, {"g", " ", "!"})
test_charsets("[[:space:]]", {" ", "\t", "\n", "\r"}, {"A", "0", "\b"})
test_charsets("[:space:]", {" ", "\t", "\n", "\r"}, {"A", "0", "\b"})
test_charsets("[[:punct:]]", {"!", "&", "."}, {"a", "X", "0", " ", "\b"})
test_charsets("[:punct:]", {"!", "&", "."}, {"a", "X", "0", " ", "\b"})
test_charsets("[[:cntrl:]]", {"\b", "\r"}, {"a", "X", "0", " "})
test_charsets("[:cntrl:]", {"\b", "\r"}, {"a", "X", "0", " "})

subheading("Character ranges")
test_charsets("[[a-z]]", {"a", "b", "y", "z"}, {" ", "X", "0", "!"})
test_charsets("[a-z]", {"a", "b", "y", "z"}, {" ", "X", "0", "!"})
test_charsets("[[a-a]]", {"a"}, {"b", "y", "z", " ", "X", "0", "!"})
test_charsets("[[b-a]]", {}, {"a", "b", "c", "y", "z", " ", "X", "0", "!"})
test_charsets("[[$-&]]", {"$", "%", "&"}, {"^", "-", "z", " ", "X", "0", "!"})
test_charsets("[[--.]]", {"-", "."}, {"+", "/", "z", " ", "X", "0", "!"})
test_charsets("[[\\[-\\]]]", {"]", "["}, {"+", "/", "z", " ", "X", "0", "!"})

subheading("Character lists")
test_charsets('["]', {'"'}, {"b", "y", "z", " ", "X", "0", "!"})
test_charsets("[\\[]", {"["}, {"]", "+", "/", "z", " ", "X", "0", "!"}) -- a single open bracket
test_charsets("[\\]]", {"]"}, {"[", "+", "/", "z", " ", "X", "0", "!"}) -- a single close bracket
test_charsets("[[\\[\\]-]]", {"]", "[", "-"}, {"+", "/", "z", " ", "X", "0", "!"})
test_charsets("[[\\]]]", {"]"}, {"[", "-", "+", "/", "z", " ", "X", "0", "!"})
test_charsets("[[aa]]", {"a"}, {"b", "y", "z", " ", "X", "0", "!"})
test_charsets("[aa]", {"a"}, {"b", "y", "z", " ", "X", "0", "!"})
test_charsets("[[abczyx]]", {"a", "b", "c", "x", "y", "z"}, {"r", "d", "m", " ", "X", "0", "!"})
test_charsets("[[-]]", {"-"}, {"b", "y", "z", " ", "X", "0", "!"})
test_charsets("[[ \t]]", {" ", "\t"}, {"\n", "b", "y", "z", "X", "0", "!"})
test_charsets("[[!#$%\\^&*()_-+=|\\\\'`~?/{}{}:;]]", 
	      {"!", "#", "$", "%", "^", "&", "*", "(", ")", "_", "-", "+", "=", "|", "\\", "'", "`", "~", "?", "/", "{", "}", "{", "}", ":", ";"},
	      {"a", "Z", " ", "\r", "\n"})

subheading("Complements")
test_charsets("[^x-]", {"b", "y", "z", "^", " ", "X", "0", "!"}, {"x", "-"})
test_charsets("[^-x]", {"b", "y", "z", "^", " ", "X", "0", "!"}, {"x", "-"})

test_charsets("[^a]", {"b", "y", "z", "^", " ", "X", "0", "!"}, {"a"})
test_charsets("[^abc]", {"d", "y", "z", "^", " ", "X", "0", "!"}, {"a", "b", "c"})
test_charsets("[^a-z]", {" ", "X", "0", "!"}, {"a", "b", "y", "z"})
test_charsets("[^ab-z]", {"c", "d", " ", "X", "0", "!"}, {"a", "b", "-", "z"}) -- NOT a range!
test_charsets("[:^digit:]", {"a", " ", "!"}, {"0", "9"})
test_charsets("[[:^space:]]", {"A", "0", "\b"}, {" ", "\t", "\n", "\r"})
test_charsets("[^[:^digit:]]+", {"0", "123"}, {"", " ", "d", "@"})
test_charsets("{[^[:^digit:]]}+", {"0", "123"}, {"", " ", "d", "@"})
test_charsets("([^[:^digit:]])+", {"0", "1 2 3"}, {"", " ", "d", "@"})
test_charsets("[^[:^alpha:]]+", {"a", "XYZ"}, {"", " ", "3", "@"})
test_charsets("{[^[:^alpha:]]}+", {"a", "XYZ"}, {"", " ", "3", "@"})
test_charsets("([^[:^alpha:]])+", {"a", "X Y Z"}, {"", " ", "3", "@"})


subheading("Unions")
test_charsets("[[:digit:][a]]", {"a", "1", "9"}, {"b", "y", "z", " ", "X", "!"})
test_charsets("[[a][:digit:]]", {"a", "1", "9"}, {"b", "y", "z", " ", "X", "!"})
test_charsets("[[a][:digit:][F-H]]", {"F", "G", "H", "a", "1", "9"}, {"f", "g", "h", "b", "y", "z", " ", "X", "!"})
test_charsets("[[:alpha:][$][2-4]]", {"F", "G", "H", "a", "2", "4", "$"}, {"5", " ", "1", "!"})
test_charsets("[[:^space:][\\n]]", {"A", "0", "\b", "\n"}, {" ", "\t", "\r"})

subheading("Complements of unions")
test_charsets("[^[:digit:]]", {"d", " ", "e", "X", "!"}, {"1", "0", "9"})
test_charsets("[^[c]]", {"d", " ", "e", "X", "4", "!"}, {"c"})
test_charsets("[^[a-c]]", {"d", " ", "e", "X", "4", "!"}, {"a", "b", "c"})
test_charsets("[^[a-c][d][:space:]]", {"e", "X", "4", "!"}, {"a", "b", "c", "d", " ", "\t"})

subheading("Whitespace and comments")
test_charsets("[[:digit:]  [a]]", {"a", "1", "9"}, {"b", "y", "z", " ", "X", "!"})
test_charsets([==[ [[a]
		    [:digit:]
		 ] ]==], {"a", "1", "9"}, {"b", "y", "z", " ", "X", "!"})
test_charsets([==[ [[a]        -- a one-char list
		    [:digit:]  -- a named set
		    [F-H]      -- and a range, all with comments in between
	   ] ]==], {"F", "G", "H", "a", "1", "9"}, {"f", "g", "h", "b", "y", "z", " ", "X", "!"})
test_charsets("[[:alpha:][$][2-4]]", {"F", "G", "H", "a", "2", "4", "$"}, {"5", " ", "1", "!"})


heading("Grammars")

subheading("Correct")

-- Grammar matches balanced numbers of a's and b's
g1_defn = [[grammar
  g1 = S ~
  S = { {"a" B} / {"b" A} / "" }
  alias A = { {"a" S} / {"b" A A} }
  B = { {"b" S} / {"a" B B} }
end]]

ok, msg = pcall(e.load, e, g1_defn)
check(ok)
check_match('g1', "", true)
check_match('g1', "ab", true)
check_match('g1', "abb", false)
check_match('g1', "a", true, 1)
check_match('g1', "a#", true, 2)

check_match('g1 $', "x", false)
check_match('g1 $', "a", false)
check_match('g1 $', "aabb", true)

m, leftover = check_match('g1', "baab", true)
check(m)
check(leftover==0)
check(m.type=="g1")
m = m.subs[1]
check(m.type=="g1.S")
m = m.subs[1]
check(m.type=="g1.S")
m = m.subs[1]
check(m.type=="g1.B")
m = m.subs[1]
check(m.type=="g1.S")
check(not m.subs)


set_expression('g1')
ok, match, leftover = e:match('g1', "baab!")
check(ok)
check(match.type=='g1', "the match of a grammar is named for the identifier bound to the grammar")
check(leftover==1, "one char left over for this match")
function collect_names(ast)
   local name = ast.type
   if ast.subs then
      return cons(name, flatten(map(collect_names, ast.subs)))
   else
      return list.new(name)
   end
end
ids = collect_names(match)
check(member('g1', ids))
check(member('g1.B', ids))			    -- name qualified by grammar id
check(not member('B', ids))		    -- unqualified name not present 
check(not member('g1.A', ids))		    -- an alias
check(not member('A', ids))		    -- ensuring this unqualified name not present

check_match('g1 [[:digit:]]', "ab 4", true)
check_match('{g1 [[:digit:]]}', "ab 4", true)	    -- because g1 is defined to end on a boundary
check_match('g1 [[:digit:]]', "ab4", false)
check_match('{g1 [[:digit:]]}', "ab4", false)

-- This grammar captures nothing!
g2_defn = [[grammar
  alias g2 = S ~
  alias S = { {"a" B} / {"b" A} / "" }
  alias A = { {"a" S} / {"b" A A} }
  alias B = { {"b" S} / {"a" B B} }
end]]

ok, msg = pcall(e.load, e, g2_defn)
check(ok)
check_match('g2', "", true, 0, "")
check_match('g2', "ab", true, 0, "ab")
check_match('g2', "baab", true, 0, "baab")
check_match('g2', "abaab", false, 0, "")

ok, ast, warnings = pcall(e.load, e, 'use_g2 = g1 g2')
check(ok, "Failed to define use_g2")
m, leftover = check_match('use_g2', "ab baab", true, 0, "ab baab")
check(m)
check(m.type=="use_g2")
check(m.subs)
check(#m.subs==1)
check(m.subs[1].type=="g1")

subheading("With errors")

g_syntax_error = [[grammar
  g1 = S ~
  S = { {"a" B} // {"b" A} / "" }
  alias A = { {"a"} / {"b" A A} }
  B = { {"b" S} / {"a" B B} }
end]]

success, pkgname, msg = e:load(g_syntax_error)
check(not success)
check(not pkgname)
check(type(msg)=="table" and msg[1])
check(violation.syntax.is(msg[1]))
check(msg[1].message:find("syntax error"))

g_left_recursion = [[grammar
  g1 = S ~
  S = { {"a" B} / {"b" A} / "" }
  alias A = { A {"a" } / {"b" A A} }
  B = { {"b" S} / {"a" B B} }
end]]

success, pkgname, msg = e:load(g_left_recursion)
check(not success)
check(not pkgname)
check(type(msg)=="table" and msg[1])
check(violation.compile.is(msg[1])) --.message:find("may be left recursive"))

g_empty_string = [[grammar
  g1 = S ~
  S = { {"a" B} / {"b" A} / "" }
  alias A = { {""}+ / {"b" A A} }
  B = { {"b" S} / {"a" B B} }
end]]

ok, pkgname, msg = e:load(g_empty_string)
check(not ok)
check(type(msg)=="table" and msg[1])
check(violation.compile.is(msg[1])) --.message:find("can match the empty string"))

g_dup_rules = [[grammar
  S = { {"a" B} / {"b" A} / "" }
  A = { {"a" S} / {"b" A A} }
  B = { {"b" S} / {"a" B B} }
  A = "this won't work"
end]]
ok, pkgname, errs = e:load(g_dup_rules)
check(not ok)
check(type(errs)=="table" and errs[1])
check(violation.compile.is(errs[1])) --.message:find("can match the empty string"))
msg = table.concat(map(violation.tostring, errs), "\n")
check(msg:find("more than one rule named 'A'"))

g_missing_rule = [[grammar
  S = { {"a" B} / {"b" A} / "" }
  A = { {"a" S} / {"b" A A} }
end]]
ok, pkgname, errs = e:load(g_missing_rule)
check(not ok)
check(type(errs)=="table" and errs[1])
check(violation.compile.is(errs[1]))
msg = table.concat(map(violation.tostring, errs), "\n")
check(msg:find("unbound identifier: B"))


heading("Invariants")

subheading("Raw and cooked versions of . and equiv identifiers")

check((e:load("dot = .")))
check((e:load("rawdot = {.}")))
check((e:load("cookeddot = (.)")))

check_match(".", "a", true)
check_match("dot", "a", true)
check_match(".", "abc", true, 2, "a")
check_match("dot", "abc", true, 2, "a")
check_match(".", "", false)
check_match("dot", "", false)

check_match("{.}", "a", true)
check_match("rawdot", "a", true)
check_match("{.}", "abc", true, 2, "a")
check_match("rawdot", "abc", true, 2, "a")
check_match("{.}", "", false)
check_match("rawdot", "", false)

check_match("(.)", "abcd", true, 3)
check_match("cookeddot", "abcd", true, 3)
check_match("(.)", "a.", true, 1, "a")
check_match("cookeddot", "a.", true, 1, "a")
check_match("(.)", "a", true, 0, "a")
check_match("cookeddot", "a", true, 0, "a")
check_match("(.)", "", false)
check_match("cookeddot", "", false)

subheading("Raw and cooked versions of the same definition")

check((e:load("import num   word=[:alpha:]+")))

m = check_match("num.int", "42", true)
check(m.type=="num.int" and (not m.subs))
m = check_match("{num.int}", "42", true)
check(m.type=="*")
check((m.subs[1]) and m.subs[1].type=="num.int")
m = check_match("(num.int)", "42", true)
check(m.type=="*")
check((m.subs[1]) and m.subs[1].type=="num.int")
--check(m.type=="num.int" and (not m.subs))

m = check_match("num.int", "42x", true, 1, "42")
check(m.type=="num.int" and (not m.subs))
m = check_match("{num.int}", "42x", true, 1, "42")
check(m.type=="*")
check((m.subs[1]) and m.subs[1].type=="num.int")
m = check_match("(num.int)", "42x", true, 1)
check(m.type=="*")
check((m.subs[1]) and m.subs[1].type=="num.int")
m = check_match("(num.int ~)", "42x", false)

m = check_match("num.int word", "42x", false)
m = check_match("{num.int word}", "42x", true, 0, "42x")
check((m.subs[1]) and m.subs[1].type=="num.int" and
      (m.subs[2]) and m.subs[2].type=="word")
m = check_match("(num.int word)", "42x", false)

m = check_match("num.int word", "42 x", true)
check((m.subs[1]) and m.subs[1].type=="num.int" and
      (m.subs[2]) and m.subs[2].type=="word")
m = check_match("{num.int word}", "42 x", false)
m = check_match("(num.int word)", "42 x", true)

check((e:load("int = num.int"))) -- word = word")))
       
m = check_match("int", "42", true)
check(m.type=="int" and (not m.subs))
m = check_match("{int}", "42", true)
check(m.type=="*")
check((m.subs[1]) and m.subs[1].type=="int")
m = check_match("(int)", "42", true)
check(m.type=="*")
check((m.subs[1]) and m.subs[1].type=="int")

m = check_match("int", "42x", true, 1, "42")
check(m.type=="int" and (not m.subs))
m = check_match("{int}", "42x", true, 1, "42")
check(m.type=="*")
check((m.subs[1]) and m.subs[1].type=="int")

m = check_match("(int)", "42x", true, 1)
m = check_match("(int ~)", "42x", false)

m = check_match("int word", "42x", false)
m = check_match("{int word}", "42x", true, 0, "42x")
check((m.subs[1]) and m.subs[1].type=="int" and
      (m.subs[2]) and m.subs[2].type=="word")
m = check_match("(int word)", "42x", false)

m = check_match("int word", "42 x", true)
check((m.subs[1]) and m.subs[1].type=="int" and
      (m.subs[2]) and m.subs[2].type=="word")
m = check_match("{int word}", "42 x", false)
m = check_match("(int word)", "42 x", true)
check((m.subs[1]) and m.subs[1].type=="int" and
      (m.subs[2]) and m.subs[2].type=="word")

check((e:load("alias int = num.int alias aword = word")))
       
m = check_match("int", "42", true)
check(m.type=="*" and m.subs[1].type=="num.int" and (not m.subs[1].subs))
m = check_match("{int}", "42", true)


m = check_match("{num.int}", "42", true)

check((m.subs[1]) and m.subs[1].type=="num.int" and (not m.subs[1].subs))
m = check_match("(int)", "42", true)
check((m.subs[1]) and m.subs[1].type=="num.int" and (not m.subs[1].subs))

m = check_match("int", "42x", true, 1, "42")
check(m.type=="*" and m.subs[1].type=="num.int" and (not m.subs[1].subs))
m = check_match("{int}", "42x", true, 1, "42")
check((m.subs[1]) and m.subs[1].type=="num.int" and (not m.subs[1].subs))
m = check_match("(int)", "42x", true, 1)
m = check_match("(int ~)", "42x", false)

m = check_match("int aword", "42x", false)
m = check_match("{int aword}", "42x", true, 0, "42x")
check((m.subs[1]) and m.subs[1].type=="num.int" and
      (m.subs[2]) and m.subs[2].type=="word")
m = check_match("(int aword)", "42x", false)

m = check_match("int aword", "42 x", true)
check((m.subs[1]) and m.subs[1].type=="num.int" and
      (m.subs[2]) and m.subs[2].type=="word")
m = check_match("{int aword}", "42 x", false)
m = check_match("(int aword)", "42 x", true)
check((m.subs[1]) and m.subs[1].type=="num.int" and
      (m.subs[2]) and m.subs[2].type=="word")

subheading("Import 'as foo' and 'as .'")

check((e:load("import num as foo")))

m = check_match("foo.float", "42.1", true)
check(m and m.type=="foo.float" and m.subs)
m = check_match("num.float", "42.1", true)	    -- and num still works
check(m.type=="num.float" and m.subs)
ok, m, left, msg = e:match("float", "42.1")	    -- float is not a top level binding
check(not ok)
check(type(m)=="table" and m[1])
check(violation.compile.is(m[1])) --.message:find("undefined identifier"))

check((e:load("import num as .")))

m = check_match("foo.float", "42.1", true)	    -- foo still works
check(m and m.type=="foo.float" and m.subs)
m = check_match("num.float", "42.1", true)	    -- and num still works
check(m.type=="num.float" and m.subs)
m = check_match("float", "42.1", true)		    -- and now float works at top level
check(m.type=="float" and m.subs, true)

subheading("Bindings (equivalence of reference and referent)")

check((e:load("foo = a / b / c")))
m = check_match("foo", "a!", true, 1, "a")
check(m.type=="foo"); check(#m.subs==1); check(m.subs[1].type=="a"); 

function test_foo()
   check_match("foo", "a!", true, 1, "a");     check_match("(a / b / c)", "a!", true, 1, "a")
   check_match("foo", "ax", true, 1);          check_match("(a / b / c)", "ax", true, 1)
   check_match("{foo}", "a!", true, 1, "a");   check_match("{(a / b / c)}", "a!", true, 1, "a")
   check_match("{foo}", "ax", true, 1);        check_match("{(a / b / c)}", "ax", true, 1)
   check_match("(foo)", "a!", true, 1, "a");   check_match("((a / b / c))", "a!", true, 1, "a")
   check_match("(foo)", "ax", true, 1);        check_match("((a / b / c))", "ax", true, 1)

end

test_foo()

check((e:load("foo = (a / b / c)")))
m = check_match("foo", "a!", true, 1, "a")
check(m.type=="foo"); check(#m.subs==1); check(m.subs[1].type=="a"); 
test_foo()

check((e:load("alias foo = a / b / c")))
m = check_match("foo", "a!", true, 1, "a")
check(m.type=="*"); check(#m.subs==1); check(m.subs[1].type=="a"); 
test_foo()

check((e:load("alias foo = (a / b / c)")))
m = check_match("foo", "a!", true, 1, "a")
check(m.type=="*"); check(#m.subs==1); check(m.subs[1].type=="a"); 
test_foo()

subheading("Sequences")

function check_bc(exp)
   check_match(exp, "b c", true)
   check_match(exp, "b c!", true, 1)
   check_match(exp, "b cx", true, 1)
   check_match(exp.." ~", "b cx", false)
   check_match(exp, "xb cx", false)
end

check_bc("b c")
check_bc("(b c)")
check_bc("{b ~ c}")

check((e:load("foo = a b c*")))
check_match('a b c*', 'a b x', true, 1, "a b ")
check_match('foo', 'a b x', true, 1, "a b ")

subheading("Quantified expressions")

function check_qe1(exp)
   check_match(exp, "a", false)
   check_match(exp, "aa", true)
   check_match(exp, "aaax", true, 1)
   check_match(exp, "aa ax", true, 3)
end

check_qe1("a{2,3}")
check_qe1("(a{2,3})")
check_qe1("{a{2,3}}")
check_qe1("{a}{2,3}")
check_qe1("{ {a}{2,3} }")

function check_qe2(exp)
   check_match(exp, "", true, 0, "")
   check_match(exp, "b", true, 0, "b")
   check_match(exp, "bxx", true, 2, "b")
   check_match(exp, " b", true, 2, "")
end

check_qe2("b?")
check_qe2("(b?)")
check_qe2("{b?}")
check_qe2("{b}?")
check_qe2("{ {b}? }")

function check_qe3a(exp)
   check_match(exp, "a b", true, 0, "a b")
   check_match(exp, "a b a b a b", true)
   check_match(exp, "a b a b a b x y", true, 4)
   check_match(exp, "a bx", true, 1)
   check_match(exp, "a x", false)
   check_match(exp, "ab a b a b", false)
   check_match(exp, "a.b", false)
end

check_qe3a("(a b)+")
check_qe3a("((a b)+)")
check_qe3a("{(a b)+}")

function check_qe3b(exp)
   check_match(exp, "a b", true, 0, "a b")
   check_match(exp, "a ba ba b", true)
   check_match(exp, "a ba ba bx y", true, 3)
   check_match(exp, "a bx", true, 1)
   check_match(exp, "a x", false)
   check_match(exp, "ab a b a b", false)
   check_match(exp, "a.b", false)
end

check_qe3b("{(a b)}+")
check_qe3b("( {(a b)}+ )")
check_qe3b("{ {(a b)}+ }")

function check_qe4a(exp)
   check_match(exp, "b", true)
   check_match(exp, "c b b b b b cx", true, 1)
   check_match(exp, "c b b b b b c x", true, 2, "c b b b b b c")
   check_match(exp, "bc", true, 1)
   check_match(exp, "", false)
end

check_qe4a("(b/c)+")
check_qe4a("( (b/c)+ )")
check_qe4a("{ (b/c)+ }")
check_qe4a("((b/c))+")
check_qe4a("({b/c})+ ")
check_qe4a("{ ({{b/c}})+ }")

function check_qe4b(exp)
   check_match(exp, "b", true)
   check_match(exp, "cbbbbbcx", true, 1)
   check_match(exp, "cbbbbbc x", true, 2)
   check_match(exp, "c c", true, 2, "c")
   check_match(exp, "", false)
end

check_qe4b("{b/c}+")
check_qe4b("( {b/c}+ )")
check_qe4b("{ {b/c}+ }")

subheading("Choice")

function check_choice1(exp)
   check_match(exp, "abc", true, 2)
   check_match(exp, "bc", true, 1)
   check_match(exp, "b", true)
   check_match(exp, "", false)
   check_match(exp, "c", false)
end

check_choice1("{a / b}")
check_choice1("{ {a} / {b} }")
check_choice1("{ {a} / b }")
check_choice1("{ {a} / b }")
check_choice1("{ a / {b} }")
check_choice1("{ a / {b} }")

function check_choice2(exp)
   check_match(exp, "abc", true, 2)
   check_match(exp, "a bc", true, 3, "a")
   check_match(exp, "b.c", true, 2, "b")
   check_match(exp, "b", true)
   check_match(exp, "", false)
   check_match(exp, "c", false)
end

check_choice2("{a} / {b}")
check_choice2("({a} / {b})")

function check_choice3(exp)
   check_match(exp, "ax", true, 1)
   check_match(exp, "bca", true, 2)
   check_match(exp, "a bc", true, 3, "a")
   check_match(exp, "b.c", true, 2, "b")
   check_match(exp, "bx", true, 1)
   check_match(exp, "", false)
   check_match(exp, "c", false)
end

check_choice3("{(a) / b}")
check_choice3("{ a / {b} }")

function check_choice4(exp)
   check_match(exp, "ax", false)
   check_match(exp, "bca", true, 2)
   check_match(exp, "a bc", true, 2, "a ")	    -- trailing space?
   check_match(exp, "", false)
   check_match(exp, "c", false)
end

check_choice4("{(a ~) / b}")
check_choice4("{ {a ~} / b }")

subheading("Sequences and choices")

function check_chs1(exp)
   check_match(exp, "a", true)
   check_match(exp, "b c", true)
   check_match(exp, "b cx", true, 1)
   check_match(exp, "bc", false)
end

check_chs1("a / b c")
check_chs1("a / (b c)")
check_chs1("a / {b ~ c}")
check_chs1("{ a / {b ~ c} }")

function check_chs2(exp)
   check_match(exp, "a", true)
   check_match(exp, "b c", false)
   check_match(exp, "bc", true)
   check_match(exp, "bcx", true, 1)
end

check_chs2("{a / b c}")
check_chs2("({a / b c})")
check_chs2("a / {b c}")
check_chs2("(a / {b c})")
check_chs2("{a / {b c}}")

subheading("Idempotence and impotence for cooked expressions")

function check_idem_etc_cooked(exp, input, expectation, leftover)
   check_match(exp, input, expectation, leftover)
   check_match("("..exp..")", input, expectation, leftover)	  -- idempotent
   check_match("{"..exp.."}", input, expectation, leftover)	  -- no-op (impotent)
   check_match("((" .. exp .. "))", input, expectation, leftover) -- idempotent
end

-- literal
check_idem_etc_cooked('"foobar"', "foobar", true)
check_idem_etc_cooked('"foobar"', "foobaZ", false)
-- identifier
check_idem_etc_cooked('.', "xyz", true, 2)
check_idem_etc_cooked('b', "bz", true, 1)
check_idem_etc_cooked('b', "b!", true, 1)
-- sequence
check_idem_etc_cooked('("foo" "bar")', "foo bar", true)
check_idem_etc_cooked('("foo" "bar")', "foobar", false)
-- choice
check_idem_etc_cooked('c / a', "c", true)
check_idem_etc_cooked('c / a', "a", true)
check_idem_etc_cooked('c / a', "ac", true, 1)
check_idem_etc_cooked('c / a', "x", false)
check_idem_etc_cooked('c / a', "", false)
-- quant
check_idem_etc_cooked('c*', "c", true)
check_idem_etc_cooked('c*', "", true)
check_idem_etc_cooked('c*', "cccx", true, 1)
check_idem_etc_cooked('c?', "c", true)
check_idem_etc_cooked('c?', "", true)
check_idem_etc_cooked('c?', "x", true, 1)
check_idem_etc_cooked('c?', "cx", true, 1)
check_idem_etc_cooked('c+', "c", true)
check_idem_etc_cooked('c+', "", false)
check_idem_etc_cooked('c+', "ccccx", true, 1)
check_idem_etc_cooked('c{2,4}', "c", false)
check_idem_etc_cooked('c{2,4}', "cc", true)
check_idem_etc_cooked('c{2,4}', "cccccc", true, 2)

check_idem_etc_cooked('(c)*', "c", true)
check_idem_etc_cooked('(c)*', "", true)
check_idem_etc_cooked('(c)*', "cccx", true, 3)
check_idem_etc_cooked('(c)?', "c", true)
check_idem_etc_cooked('(c)?', "", true)
check_idem_etc_cooked('(c)?', "x", true, 1)
check_idem_etc_cooked('(c)?', "cx", true, 1)
check_idem_etc_cooked('(c)+', "c", true)
check_idem_etc_cooked('(c)+', "c c c", true)
check_idem_etc_cooked('(c)+', "c c cx", true, 1)
check_idem_etc_cooked('(c)+', "", false)
check_idem_etc_cooked('(c)+', "ccccx", true, 4)
check_idem_etc_cooked('(c){2,4}', "c", false)
check_idem_etc_cooked('(c){2,4}', "cc", false)
check_idem_etc_cooked('(c){2,4}', "c c", true)
check_idem_etc_cooked('(c){2,4}', "c c c c c c", true, 4)

subheading("Idempotency and impotence for raw expressions")

function check_idem_etc_raw(exp, input, expectation, leftover)
   assert(exp:sub(1,1)=="{")
   check_match("("..exp..")", input, expectation, leftover)	-- no-op
   check_match("{" .. exp .. "}", input, expectation, leftover) -- idempotent
end

-- literal
check_idem_etc_raw('{"foobar"}', "foobar", true)
check_idem_etc_raw('{"foobar"}', "foobaZ", false)
-- identifier
check_idem_etc_raw('{.}', "xyz", true, 2)
check_idem_etc_raw('{b}', "bz", true, 1)
check_idem_etc_raw('{b}', "b!", true, 1)
-- sequence
check_idem_etc_raw('{("foo" "bar")}', "foo bar", true)
check_idem_etc_raw('{("foo" "bar")}', "foobar", false)
-- choice
check_idem_etc_raw('{c / a}', "c", true)
check_idem_etc_raw('{c / a}', "a", true)
check_idem_etc_raw('{c / a}', "ac", true, 1)
check_idem_etc_raw('{c / a}', "x", false)
check_idem_etc_raw('{c / a}', "", false)
-- quant
check_idem_etc_raw('{c*}', "c", true)
check_idem_etc_raw('{c*}', "", true)
check_idem_etc_raw('{c*}', "cccx", true, 1)
check_idem_etc_raw('{c?}', "c", true)
check_idem_etc_raw('{c?}', "", true)
check_idem_etc_raw('{c?}', "x", true, 1)
check_idem_etc_raw('{c?}', "cx", true, 1)
check_idem_etc_raw('{c+}', "c", true)
check_idem_etc_raw('{c+}', "", false)
check_idem_etc_raw('{c+}', "ccccx", true, 1)
check_idem_etc_raw('{c{2,4}}', "c", false)
check_idem_etc_raw('{c{2,4}}', "cc", true)
check_idem_etc_raw('{c{2,4}}', "cccccc", true, 2)

check_idem_etc_raw('{(c)*}', "c", true)
check_idem_etc_raw('{(c)*}', "", true)
check_idem_etc_raw('{(c)*}', "cccx", true, 3)
check_idem_etc_raw('{(c)?}', "c", true)
check_idem_etc_raw('{(c)?}', "", true)
check_idem_etc_raw('{(c)?}', "x", true, 1)
check_idem_etc_raw('{(c)?}', "cx", true, 1)
check_idem_etc_raw('{(c)+}', "c", true)
check_idem_etc_raw('{(c)+}', "c c c", true)
check_idem_etc_raw('{(c)+}', "c c cx", true, 1)
check_idem_etc_raw('{(c)+}', "", false)
check_idem_etc_raw('{(c)+}', "ccccx", true, 4)
check_idem_etc_raw('{(c){2,4}}', "c", false)
check_idem_etc_raw('{(c){2,4}}', "cc", false)
check_idem_etc_raw('{(c){2,4}}', "c c", true)
check_idem_etc_raw('{(c){2,4}}', "c c c c c c", true, 4)

---------------------------------------------------------------------------------------------------
heading("Hash tags and string literals")
---------------------------------------------------------------------------------------------------

r, err = e:compile("#x")
check(not r)					    -- not a pattern

function check_message(msg_text)
   r, err = e:compile("message:#" .. msg_text)
   check(r, "did not compile", 1)
   if not r then return; end
   m, last = r:match("")
   check(m, "did not match", 1)
   check(m.type=="*", "type not anon", 1)
   check(m.subs and m.subs[1], "no subs???", 1)
   check(m.subs[1].type=="message", "sub not called 'message'", 1)
   -- strip quotes off
   if msg_text:sub(1,1)=='"' then msg_text = msg_text:sub(2, -2); end
   check(m.subs[1].data==msg_text, "data not '" .. msg_text .. "' (was '" .. m.subs[1].data .. "')", 1)
end

check_message("x")
check_message("xyz_123")
check_message('"This is a long message!"')

data = 'abcdef123ghi'
-- COOKED
r, err = e:compile("message:(#" .. data .. ")")
check(r, "did not compile")
m = r:match("foo")
check(m, "did not match")
check(m.subs and m.subs[1] and m.subs[1].type=="message")
check(m.subs[1].data==data)
-- RAW
r, err = e:compile("message:{#" .. data .. "}")
check(r, "did not compile")
m = r:match("foo")
check(m, "did not match")
check(m.subs and m.subs[1] and m.subs[1].type=="message")
check(m.subs[1].data==data)

r, err = e:compile('message:(#"", #msg_name)')
check(r, "did not compile")
m = r:match("foo")
check(m, "did not match")
check(m.subs and m.subs[1] and m.subs[1].type=="msg_name")
check(m.subs[1].data=="")

r, err = e:compile('message:(#"hello world", #"")')
check(not r, "should not have compiled")
check(violation.tostring(err[1]):find("not a tag"))
check(violation.tostring(err[1]):find("string value"))

r, err = e:compile('message:(#"message text here", #msg_name)')
check(r, "did not compile")
m = r:match("foo")
check(m, "did not match")
check(m.subs and m.subs[1] and m.subs[1].type=="msg_name")
check(m.subs[1].data=="message text here")

r, err = e:compile('message:(#msg_text, #"message name")')
check(not r, "should not compile because second arg not a tag")
check(violation.tostring(err[1]):find("not a tag"))
check(violation.tostring(err[1]):find("string value"))

r, err = e:compile("message:abc")
check(not r)					    -- abc is undefined
check(violation.tostring(err[1]):find("unbound identifier: abc"))
r, err = e:compile('message:("hi", "bye", "three")')
check(not r)					    -- too many args
check(violation.tostring(err[1]):find("3 given"))
r, err = e:compile('message:()')
check(not r)					    -- too few args
check(violation.tostring(err[1]):find("extraneous input"))
r, err = e:compile('message:(message)')
check(not r)					    -- wrong arg type (pfunction, not pattern)

---------------------------------------------------------------------------------------------------
heading("Lookarounds")
---------------------------------------------------------------------------------------------------

function check_look(invert, extra_prefix)

   local not_fn = function(x) return not x end
   local identity = function(x) return x end
   local pre = (extra_prefix or "")
   local switch = invert and not_fn or identity

   check_match(pre..'>"x"', 'x', switch(true), 1)
   check_match(pre..'>"x"', 'xyz', switch(true), 3)
   check_match(pre..'>"x"', '', switch(false), 0)
   check_match(pre..'>"x"', 'y', switch(false), 1)

   check_match('{"w"'..pre..'>"x"}', 'wx', switch(true), 1)
   check_match('{"w"'..pre..'>"x"}', 'wxyz', switch(true), 3)
   check_match('{"w"'..pre..'>"x"}', 'w', switch(false), 0)
   check_match('{"w"'..pre..'>"x"}', 'wy', switch(false), 1)

   check_match('"w"'..pre..'>"x"', 'w x', switch(true), 1)
   check_match('"w"'..pre..'>"x"', 'w xyz', switch(true), 3)
   check_match('"w"'..pre..'>"x"', 'w', switch(false), 0)
   check_match('"w"'..pre..'>"x"', 'w \t\t', switch(false), 0)
   check_match('"w"'..pre..'>"x"', 'w y', switch(false), 1)

end

check_look(false)
check_look(true, "!")
check_look(false, "!!")				    -- two wrongs make a right :)

check_look(false, ">")
check_look(false, ">>")
check_look(false, ">!>!")
check_look(false, "!!>!>!")

check_look(true, "!>")
check_look(true, "!>")
check_look(true, "!!>!")
check_look(true, "!!>>!")
check_look(true, "!!>!>!!")

function check_lookbehind(invert, extra_prefix)

   local not_fn = function(x) return not x end
   local identity = function(x) return x end
   local pre = (extra_prefix or "")
   local switch = invert and not_fn or identity

   check_match(pre..'{.<"x"}', 'x', switch(true), 0)
   check_match(pre..'{.<"x"}', 'xyz', switch(true), 2)
   check_match(pre..'{<"x"}', '', switch(false), 0)
   check_match(pre..'{.<"x"}', 'y', switch(false), 1)

   check_match('{"w".'..pre..'<"x"}', 'wx', switch(true), 0)
   check_match('{"w".'..pre..'<"x"}', 'wxyz', switch(true), 2)
   check_match('{"w".'..pre..'<"x"}', 'w/', switch(false), 0)
   check_match('{"w".'..pre..'<"x"}', 'wyz', switch(false), 1)

   check_match('"w".'..pre..'<"x"', 'w x', switch(true), 0)
   check_match('"w"{.'..pre..'<"x"}', 'w xyz', switch(true), 2)
   check_match('"w"{.'..pre..'<"x"}', 'w 3333', switch(false), 3)
   check_match('"w"'..pre..'<"x"', 'w \t\t', switch(false), 0)
   check_match('"w".'..pre..'<"x"', 'w y', switch(false), 0)

end

check_lookbehind(false)
check_lookbehind(true, "!")

---------------------------------------------------------------------------------------------------
heading("Allowing bindings in any order in a block")

s = 'a = "a"; a = "b"'
ok, _, errs = e:load(s)
check(not ok)
m = table.concat(map(violation.tostring, errs), "\n")
check(m:find("already bound"))

s = 'b = "b"; a = "a"'
ok, _, errs = e:load(s)
check(ok)
check_match("a b a", "a b a", true, 0)

s = 'a = "a"; b = a'
ok, _, errs = e:load(s)
check(ok)
check_match("a b a", "a a a", true, 0)

s = 'b = a; a = "a"'
ok, _, errs = e:load(s)
check(ok)
check(#errs==0)
check_match("a b a", "a a a", true, 0)

s = 'a = b; b = a'
ok, _, errs = e:load(s)
check(not ok)
msg = table.concat(map(violation.tostring, errs), "\n")
check(msg:find("mutual dependencies"))


---------------------------------------------------------------------------------------------------
heading("Ok to use 'alias' and 'local' as identifiers")
	
check((e:load('alias = "foo"')))
ok, m = e:match('alias', "foo")
check(ok)
check(m and m.type=="alias" and m.s==1 and m.e==4 and m.data=='foo')
check((e:load('local alias = "bar"')))
ok, m = e:match('alias', "foo")
check(ok)
check(not m)
ok, m = e:match('alias', "bar")
check(ok)
check(m and m.type=="alias" and m.s==1 and m.e==4 and m.data=='bar')

check((e:load('local alias alias = "bar"')))
ok, m = e:match('alias', "bar")
check(ok)
check(m and m.type=="*" and m.s==1 and m.e==4 and m.data=='bar')

check((e:load('local = "oklocal"')))
ok, m = e:match('local', "oklocal")
check(ok)
check(m and m.type=="local" and m.s==1 and m.e==8 and m.data=='oklocal')

check((e:load('local local = "oklocallocal"')))
ok, m = e:match('local', "oklocal")
check(ok)
check(not m)

ok, m = e:match('local', "oklocallocal")
check(m and m.type=="local" and m.s==1 and m.e==13 and m.data=='oklocallocal')

check((e:load('local alias local = "oklocalaliaslocal"')))
ok, m = e:match('local', "oklocallocal")
check(ok)
check(not m)

ok, m = e:match('local', "oklocalaliaslocal")
check(ok)
check(m and m.type=="*" and m.s==1 and m.e==18 and m.data=='oklocalaliaslocal')

check((e:load('grammar = "okgrammar"')))
ok, m = e:match('grammar', "okgrammar")
check(ok)
check(m and m.type=="grammar" and m.s==1 and m.e==10 and m.data=='okgrammar')

check((e:load('alias grammar = "okaliasgrammar"')))
ok, m = e:match('grammar', "okgrammar")
check(ok)
check(not m)

ok, m = e:match('grammar', "okaliasgrammar")
check(ok)
check(m and m.type=="*" and m.s==1 and m.e==15 and m.data=='okaliasgrammar')

check(not ((e:load('alias local grammar = "wrong order of declaration keywords"'))))

check((e:load('local alias grammar = "oklocalaliasgrammar"')))
ok, m = e:match('grammar', "okaliasgrammar")
check(ok)
check(not m)

ok, m = e:match('grammar', "oklocalaliasgrammar")
check(ok)
check(m and m.type=="*" and m.s==1 and m.e==20 and m.data=='oklocalaliasgrammar')

check((e:load('end = "okend"')))
ok, m = e:match('end', "okend")
check(ok)
check(m and m.type=="end" and m.s==1 and m.e==6 and m.data=='okend')

check((e:load('alias end = "okaliasend"')))
ok, m = e:match('end', "okend")
check(ok)
check(not m)

ok, m = e:match('end', "okaliasend")
check(ok)
check(m and m.type=="*" and m.s==1 and m.e==11 and m.data=='okaliasend')

check(not ((e:load('alias local end = "wrong order of declaration keywords"'))))

check((e:load('local alias end = "oklocalaliasend"')))
ok, m = e:match('end', "okaliasend")
check(ok)
check(not m)

ok, m = e:match('end', "oklocalaliasend")
check(ok)
check(m and m.type=="*" and m.s==1 and m.e==16 and m.data=='oklocalaliasend')

heading("Cannot define same id twice in a file")

function check_dup_id(filename)
   ok, pkgname, errs = e:loadfile(TEST_HOME .. "/" .. filename)
   check(not ok)
   check(not pkgname, "pkgname is: " .. tostring(pkgname))
   msg = table.concat(map(violation.tostring, errs), "\n")
   check(msg:find("identifier already bound"), "error was:\n" .. msg)
end

check_dup_id("dup-id1.rpl")
check_dup_id("dup-id2.rpl")
check_dup_id("dup-id3.rpl")

e.searchpath = TEST_HOME .. ":" .. e.searchpath
ok, pkgname, errs = e:import("dup-id4")
check(not ok)
check(not pkgname, "pkgname is: " .. tostring(pkgname))
msg = table.concat(map(violation.tostring, errs), "\n")
check(msg:find("identifier already bound"), "error was:\n" .. msg)

heading("And-exp")

-- These cannot succeed, no matter what the input
check_match('"a" & "b"', "a", false)
check_match('"a" & "b"', "", false)
check_match('"a" & "b"', "b", false)
check_match('"a" & "b"', "ab", false)

-- Check that whitespace is not needed
check_match('"a"& "a"', "a", true, 0)
check_match('"a" &"a"', "a", true, 0)
check_match('"a"&"a"', "a", true, 0)
check_match('.& "a"', "a", true, 0)
check_match('"a" &.', "a", true, 0)
check_match('.&.', "a", true, 0)
check_match('"a"&"a"&"a"', "a", true, 0)
check_match('"a"&"a"&.', "a", true, 0)
check_match('"a"&.&"a"', "a", true, 0)
check_match('.&"a"&"a"', "a", true, 0)

check_match('"a" & "a"', "a", true, 0)
check_match('"a" & "aa"', "a", false)
check_match('"a" & "aa"', "aa", true, 0)
check_match('"aa" & "a"', "aa", true, 1)

check_match('"a" & ("a"/"b")', "a", true, 0)
check_match('("a"/"b") & "a"', "a", true, 0)
check_match('("a"/"b") & "b"', "b", true, 0)

check_match('[:alpha:] & [:alpha:] & "a"', "a", true, 0)
check_match('[:alpha:] & [:alpha:] & "x"', "x", true, 0)
check_match('[:alpha:] & [:alpha:] & "x"', "a", false)
check_match('[:alpha:] & [:alpha:] & [:alpha:] & [:alpha:]', "q", true, 0)
check_match('[:alpha:] & [:alpha:] & [:alpha:] & [:alpha:]', "1", false)

check_match('[:alpha:] & . & [:alpha:] & [:alpha:]', "q", true, 0)
check_match('[:alpha:] & [:alpha:] & [:alpha:] & . ', "q", true, 0)
check_match('[:alpha:] & [:alpha:] & [:alpha:] & . ', "1", false)

check_match('{"a"{3} "b"} & .*', "aaab", true, 0)
check_match('{"a"{3} "b"} & .*', "aaabdef", true, 0)
check_match('{"a"{3} "b"} & .*', "xaaab", false)

check_match('.* & {"a"{3} "b"}', "aaab", true, 0)
check_match('.* & {"a"{3} "b"}', "aaabdef", true, 3)
check_match('.* & {"a"{3} "b"}', "xaaab", false)


-- return the test results in case this file is being called by another one which is collecting
-- up all the results:
return test.finish()
