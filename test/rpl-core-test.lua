---- -*- Mode: Lua; -*- 
----
---- rpl-core-test.lua
----
---- (c) 2016, Jamie A. Jennings
----

test = require "test-functions"
json = require "cjson"

check = test.check
heading = test.heading
subheading = test.subheading

eid = false;

function set_expression(exp)
   local ok, msg = api.configure_engine(eid, json.encode{expression=exp, encode=false})
   if not ok then error("Configuration error: " .. msg); end
end

function check_match(exp, input, expectation, expected_leftover, expected_text, addlevel)
   expected_leftover = expected_leftover or 0
   addlevel = addlevel or 0
   set_expression(exp)
   local ok, retvals_js = api.match(eid, input)
   check(ok, "failed call to api.match")
   local retvals = json.decode(retvals_js)
   local m, leftover = retvals[1], retvals[2]
   check(expectation == (not (not m)), "expectation not met: " .. exp .. " " ..
	 ((m and "matched") or "did NOT match") .. " '" .. input .. "'", 1+addlevel)
   local fmt = "expected leftover matching %s against '%s' was %d but received %d"
   if m then
      check(leftover==expected_leftover,
	    string.format(fmt, exp, input, expected_leftover, leftover), 1+addlevel)
      if expected_text and m then
	 local name, match = next(m)
	 local text = match.text
	 local fmt = "expected text matching %s against '%s' was '%s' but received '%s'"
	 check(expected_text==text,
	       string.format(fmt, exp, input, expected_text, text), 1+addlevel)
      end
   end
   return retvals
end
      
test.start(test.current_filename())

----------------------------------------------------------------------------------------
heading("Setting up")
----------------------------------------------------------------------------------------
api = require "api"

check(type(api)=="table")
check(api.API_VERSION)
check(type(api.API_VERSION=="string"))

check(type(api.new_engine)=="function")
ok, eid_js = api.new_engine(json.encode{name="rpl core test"})
check(ok)
eid = json.decode(eid_js)[1]
check(type(eid)=="string")

subheading("Setting up assignments")
ok, msg = api.load_string(eid, 'a = "a"  b = "b"  c = "c"  d = "d"')
check(ok)
ok, msg = api.get_binding(eid, "a")
check(ok)

set_expression('a')
ok, match_js = api.match(eid, "a")
check(ok)
match = json.decode(match_js)
check(next(match[1])=="a", "the match of an identifier is named for the identifier")

set_expression('(a)')
ok, match_js = api.match(eid, "a")
check(ok)
match = json.decode(match_js)
check(next(match[1])=="a", "the match of an expression is usually anonymous, but cooking an identifier is redundant")
subs = match[1]["a"].subs
check(not subs)

set_expression('{a}')
ok, match_js = api.match(eid, "a")
check(ok)
match = json.decode(match_js)
check(next(match[1])=="*", "the match of an expression is anonymous")
subs = match[1]["*"].subs
check(subs)
submatchname = next(subs[1])
check(submatchname=="a", "the only sub of this expression is the identifier in the raw group")

ok, msg = api.load_string(eid, 'alias plain_old_alias = "p"')
check(ok)

ok, msg = api.load_string(eid, 'alias alias_to_plain_old_alias = plain_old_alias')
check(ok)

ok, msg = api.load_string(eid, 'alias alias_to_a = a')
check(ok)

ok, msg = api.load_string(eid, 'alternate_a = a')
check(ok)

ok, msg = api.load_string(eid, 'alternate_to_alias_to_a = alias_to_a')
check(ok)

ok, msg = api.load_string(eid, 'alias alias_to_alternate_to_alias_to_a = alias_to_a')
check(ok)

subheading("Testing re-assignments")

check_match('plain_old_alias', "x", false, 1)
result = check_match('plain_old_alias', "p", true)
check(next(result[1])=="*", "the match of an alias is anonymous")
check(not result[1]["*"].subs, "no subs")

check_match('alias_to_plain_old_alias', "x", false, 1)
result = check_match('alias_to_plain_old_alias', "p", true)
check(next(result[1])=="*", "the match of an alias is anonymous")
check(not result[1]["*"].subs, "no subs")

match = check_match('alias_to_a', "a", true)
check(next(match[1])=="*", 'an alias can be used as a top-level exp, and the match is labeled "*"')
subs = match[1]["*"].subs
check(#subs==1)
check(next(subs[1])=="a")

match = check_match('alternate_a', "a", true)
check(next(match[1])=="alternate_a", 'the match is labeled with the identifier name to which it is bound')
subs = match[1]["alternate_a"].subs
check(#subs==1)
check(next(subs[1])=="a")

match = check_match('alternate_to_alias_to_a', "a", true)
check(next(match[1])=="alternate_to_alias_to_a", 'rhs of an assignment can contain an alias, and it will be captured')
subs = match[1]["alternate_to_alias_to_a"].subs
check(#subs==1)
check(next(subs[1])=="a")

match = check_match('alias_to_alternate_to_alias_to_a', "a", true)
check(next(match[1])=="*", 'an alias can be used as a top-level exp, and the match is labeled "*"')
subs = match[1]["*"].subs
check(#subs==1)
check(next(subs[1])=="a")

----------------------------------------------------------------------------------------
heading("Literals")
----------------------------------------------------------------------------------------
subheading("Built-ins")

set_expression('.')
ok, match_js = api.match(eid, "a")
check(ok)
match = json.decode(match_js)
check(next(match[1])=="*", "the match of an alias is anonymous")

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
check_match('...', "Hello", false)
check_match('...', "H e llo", true, 2)
check_match('(...)', "H e llo", true, 2)
check_match('(...)', "H e l lo", true, 3)
check_match('{...}', "H e llo", true, 4, "H e")
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
check_match('@a', "x", false)
check_match('@a', "a", true, 1, "")
check_match('@a', "ayz", true, 3, "")		    -- ???
check_match('@{a}', "ayz", true, 3, "")
check_match('@(a)', "ayz", true, 3, "")		    -- ???
check_match('(@a)', "ayz", true, 3, "")
check_match('(@{a})', "ayz", true, 3, "")
check_match('(@(a))', "ayz", true, 3, "")

check_match('@a', "xyz", false)
check_match('(@a)', "xyz", false, 4, "")
check_match('{@a}', "axyz", true, 4, "")
check_match('{@a}', "xyz", false, 4, "")
check_match('@(a)', "axyz", true, 4, "")	    -- ???
check_match('(@(a))', "axyz", true, 4, "")	    -- ???
check_match('@{a~}', "a.xyz", true, 5, "")
check_match('(@(a~))', "a.xyz", true, 5, "")	    -- ???

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
check_match('!{a~}', "axyz", true, 4, "")
check_match('!(a~)', "axyz", true, 4, "")	    -- ???



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
ok, msg = api.load_string(eid, "token = { ![[:space:]] . {!~ .}* }")
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
check_match('(~token)*', '\tThe quick, brown fox.\nSentence fragment!!  ', true, 2)
check_match('(~token~)*', '\tThe quick, brown fox.\nSentence fragment!!  ', true, 0)
check_match('{~token~}*', '\tThe quick, brown fox.\nSentence fragment!!  ', true, 0)

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
check_match('{a*}', 'aaaaaa ', true, 1)		    -- !@# let's not capture the trailing boundary
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
check_match('(a)+', 'aa', false)
check_match('(a)+', 'a a a a', true)
check_match('(a)+', 'a a a a    ', true)
check_match('(a)+', 'a a a a x', true, 1)
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
check_match('c{,0}', '', true)
check_match('c{,0}', 'x', true, 1)		    -- because start of input is a boundary
check_match('c{,0}', 'c', true)
check_match('c{,0}', 'cx', true, 1)
check_match('c{,0}~', 'cx', false)
check_match('c{,0}', 'c x', true, 2)
check_match('c{,0}', ' x', true, 2)
check_match('c{,0}', '!', true, 1)
check_match('c{,0}', 'cccccccccc x', true, 2)

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
check_match('{c{,0}}', '', true)
check_match('{c{,0}}', 'x', true, 1)		    -- because start of input is a boundary
check_match('{c{,0}}', 'c', true)
check_match('{c{,0}}', 'cx', true, 1)
check_match('{c{,0}}', 'c x', true, 2)
check_match('{c{,0}}', ' x', true, 2)
check_match('{c{,0}}', '!', true, 1)
check_match('{c{,0}}', 'cccccccccc x', true, 2)

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
		     "[^]",
		     "[xyz^]",
		     "[[abc] / [def]]",
		     "[[a-z] misplaced_identifier [def]]",
		     "[[a-z] [def]",		    -- no final closing bracket
		     "[]",			    -- this was legal before v0.99?
                     "[[abc][]]"} do
   ok, msg = api.configure_engine(eid, json.encode({expression=exp}))
   check(not ok, "this expression was expected to fail: " .. exp)
   check(msg:find("Syntax error at line 1"), "Did not get syntax error for exp " ..
      exp .. ".  Message was: " .. msg)
end
ok, msg = api.configure_engine(eid, json.encode{expression="[:foobar:]"})
check(not ok)
check(msg:find("named charset not defined"))

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
test_charsets("[[b-a]]", {}, {"a", "b", "c", "y", "z", " ", "X", "0", "!"}) -- !@# could war
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
test_charsets("[^a]", {"b", "y", "z", "^", " ", "X", "0", "!"}, {"a"})
test_charsets("[^abc]", {"d", "y", "z", "^", " ", "X", "0", "!"}, {"a", "b", "c"})
test_charsets("[:^digit:]", {"a", " ", "!"}, {"0", "9"})
test_charsets("[[:^space:]]", {"A", "0", "\b"}, {" ", "\t", "\n", "\r"})
test_charsets("[^a-z]", {" ", "X", "0", "!"}, {"a", "b", "y", "z"})
test_charsets("[^ab-z]", {"c", "d", " ", "X", "0", "!"}, {"a", "b", "-", "z"}) -- NOT a range!
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

-- Grammar matches balanced numbers of a's and b's
g1_defn = [[grammar
  g1 = S ~
  S = { {"a" B} / {"b" A} / "" }
  alias A = { {"a" S} / {"b" A A} }
  B = { {"b" S} / {"a" B B} }
end]]

ok, msg = api.load_string(eid, g1_defn)
check(ok)
check_match('g1', "", true)
check_match('g1', "ab", true)
check_match('g1', "baab", true)
check_match('g1', "abb", false)
check_match('g1', "a", true, 1)
check_match('g1', "a#", true, 2)

check_match('g1$', "x", false)
check_match('g1$', "a", false)
check_match('g1$', "aabb", true)

set_expression('g1')
ok, match_js = api.match(eid, "baab!")
check(ok)
check(match_js)
match = json.decode(match_js)
check(next(match[1])=='g1', "the match of a grammar is named for the identifier bound to the grammar")
check(match[2]==1, "one char left over for this match")
function collect_names(ast)
   local name = next(ast)
   if ast[name].subs then
      return cons(name, flatten(map(collect_names, ast[name].subs)))
   else
      return list(name)
   end
end
ids = collect_names(match[1])
check(member('g1', ids))
check(member('B', ids))
check(not member('A', ids))			    -- an alias

check_match('g1 [[:digit:]]', "ab 4", true)
check_match('{g1 [[:digit:]]}', "ab 4", true)	    -- because g1 is defined to end on a boundary
check_match('g1 [[:digit:]]', "ab4", false)
check_match('{g1 [[:digit:]]}', "ab4", false)

heading("Invariants")

subheading("Raw and cooked versions of . and equiv identifiers")

check((api.load_string(eid, "dot = .")))
check((api.load_string(eid, "rawdot = {.}")))
check((api.load_string(eid, "cookeddot = (.)")))

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

check((api.load_manifest(eid, "$sys/MANIFEST")))

m = check_match("common.int", "42", true)
check((not m[1]["*"]) and m[1]["common.int"] and (not m[1]["common.int"].subs))
m = check_match("{common.int}", "42", true)
check((m[1]["*"].subs[1]) and m[1]["*"].subs[1]["common.int"] and (not m[1]["*"].subs[1]["common.int"].subs))
m = check_match("(common.int)", "42", true)
check((not m[1]["*"]) and m[1]["common.int"] and (not m[1]["common.int"].subs))
--check((m[1]["*"].subs[1]) and m[1]["*"].subs[1]["common.int"] and (not m[1]["*"].subs[1]["common.int"].subs))

m = check_match("common.int", "42x", true, 1, "42")
check((not m[1]["*"]) and m[1]["common.int"] and (not m[1]["common.int"].subs))
m = check_match("{common.int}", "42x", true, 1, "42")
check((m[1]["*"].subs[1]) and m[1]["*"].subs[1]["common.int"] and (not m[1]["*"].subs[1]["common.int"].subs))
m = check_match("(common.int)", "42x", true, 1)
m = check_match("(common.int ~)", "42x", false)

m = check_match("common.int common.word", "42x", false)
m = check_match("{common.int common.word}", "42x", true, 0, "42x")
check((m[1]["*"].subs[1]) and m[1]["*"].subs[1]["common.int"] and
      (m[1]["*"].subs[2]) and m[1]["*"].subs[2]["common.word"])
m = check_match("(common.int common.word)", "42x", false)

m = check_match("common.int common.word", "42 x", true)
check((m[1]["*"].subs[1]) and m[1]["*"].subs[1]["common.int"] and
      (m[1]["*"].subs[2]) and m[1]["*"].subs[2]["common.word"])
m = check_match("{common.int common.word}", "42 x", false)
m = check_match("(common.int common.word)", "42 x", true)

check((api.load_string(eid, "int = common.int word = common.word")))
       
m = check_match("int", "42", true)
check((not m[1]["*"]) and m[1]["int"] and (#m[1]["int"].subs==1))
m = check_match("{int}", "42", true)
check((m[1]["*"].subs[1]) and m[1]["*"].subs[1]["int"] and (#m[1]["*"].subs[1]["int"].subs==1))
m = check_match("(int)", "42", true)
check((not m[1]["*"]) and m[1]["int"] and (#m[1]["int"].subs==1))
--check((m[1]["*"].subs[1]) and m[1]["*"].subs[1]["int"] and (#m[1]["*"].subs[1]["int"].subs==1))

m = check_match("int", "42x", true, 1, "42")
check((not m[1]["*"]) and m[1]["int"] and (#m[1]["int"].subs==1))
m = check_match("{int}", "42x", true, 1, "42")
check((m[1]["*"].subs[1]) and m[1]["*"].subs[1]["int"] and (#m[1]["*"].subs[1]["int"].subs==1))
m = check_match("(int)", "42x", true, 1)
m = check_match("(int ~)", "42x", false)

m = check_match("int word", "42x", false)
m = check_match("{int word}", "42x", true, 0, "42x")
check((m[1]["*"].subs[1]) and m[1]["*"].subs[1]["int"] and
      (m[1]["*"].subs[2]) and m[1]["*"].subs[2]["word"])
m = check_match("(int word)", "42x", false)

m = check_match("int word", "42 x", true)
check((m[1]["*"].subs[1]) and m[1]["*"].subs[1]["int"] and
      (m[1]["*"].subs[2]) and m[1]["*"].subs[2]["word"])
m = check_match("{int word}", "42 x", false)
m = check_match("(int word)", "42 x", true)
check((m[1]["*"].subs[1]) and m[1]["*"].subs[1]["int"] and
      (m[1]["*"].subs[2]) and m[1]["*"].subs[2]["word"])

check((api.load_string(eid, "alias int = common.int alias word = common.word")))
       
m = check_match("int", "42", true)
check(m[1]["*"] and m[1]["*"].subs[1]["common.int"] and (not m[1]["*"].subs[1]["common.int"].subs))
m = check_match("{int}", "42", true)
check((m[1]["*"].subs[1]) and m[1]["*"].subs[1]["common.int"] and (not m[1]["*"].subs[1]["common.int"].subs))
m = check_match("(int)", "42", true)
check((m[1]["*"].subs[1]) and m[1]["*"].subs[1]["common.int"] and (not m[1]["*"].subs[1]["common.int"].subs))

m = check_match("int", "42x", true, 1, "42")
check(m[1]["*"] and m[1]["*"].subs[1]["common.int"] and (not m[1]["*"].subs[1]["common.int"].subs))
m = check_match("{int}", "42x", true, 1, "42")
check((m[1]["*"].subs[1]) and m[1]["*"].subs[1]["common.int"] and (not m[1]["*"].subs[1]["common.int"].subs))
m = check_match("(int)", "42x", true, 1)
m = check_match("(int ~)", "42x", false)

m = check_match("int word", "42x", false)
m = check_match("{int word}", "42x", true, 0, "42x")
check((m[1]["*"].subs[1]) and m[1]["*"].subs[1]["common.int"] and
      (m[1]["*"].subs[2]) and m[1]["*"].subs[2]["common.word"])
m = check_match("(int word)", "42x", false)

m = check_match("int word", "42 x", true)
check((m[1]["*"].subs[1]) and m[1]["*"].subs[1]["common.int"] and
      (m[1]["*"].subs[2]) and m[1]["*"].subs[2]["common.word"])
m = check_match("{int word}", "42 x", false)
m = check_match("(int word)", "42 x", true)
check((m[1]["*"].subs[1]) and m[1]["*"].subs[1]["common.int"] and
      (m[1]["*"].subs[2]) and m[1]["*"].subs[2]["common.word"])

subheading("Bindings (equivalence of reference and referent)")

check((api.load_string(eid, "foo = a / b / c")))
m = check_match("foo", "a!", true, 1, "a")
check(m[1]["foo"]); check(#m[1]["foo"].subs==1); check(m[1]["foo"].subs[1]["a"]); 

function test_foo()
   check_match("foo", "a!", true, 1, "a");     check_match("(a / b / c)", "a!", true, 1, "a")
   check_match("foo", "ax", true, 1);          check_match("(a / b / c)", "ax", true, 1)
   check_match("{foo}", "a!", true, 1, "a");   check_match("{(a / b / c)}", "a!", true, 1, "a")
   check_match("{foo}", "ax", true, 1);        check_match("{(a / b / c)}", "ax", true, 1)
   check_match("(foo)", "a!", true, 1, "a");   check_match("((a / b / c))", "a!", true, 1, "a")
   check_match("(foo)", "ax", true, 1);        check_match("((a / b / c))", "ax", true, 1)

end

test_foo()

check((api.load_string(eid, "foo = (a / b / c)")))
m = check_match("foo", "a!", true, 1, "a")
check(m[1]["foo"]); check(#m[1]["foo"].subs==1); check(m[1]["foo"].subs[1]["a"]); 
test_foo()

check((api.load_string(eid, "alias foo = a / b / c")))
m = check_match("foo", "a!", true, 1, "a")
check(m[1]["*"]); check(#m[1]["*"].subs==1); check(m[1]["*"].subs[1]["a"]); 
test_foo()

check((api.load_string(eid, "alias foo = (a / b / c)")))
m = check_match("foo", "a!", true, 1, "a")
check(m[1]["*"]); check(#m[1]["*"].subs==1); check(m[1]["*"].subs[1]["a"]); 
test_foo()

subheading("Sequences")

function check_bc(exp)
   check_match(exp, "b c", true)
   check_match(exp, "b c!", true, 1)
   check_match(exp, "b cx", true, 1)
   check_match(exp.."~", "b cx", false)
   check_match(exp, "xb cx", false)
end

check_bc("b c")
check_bc("(b c)")
check_bc("{b ~ c}")

check((api.load_string(eid, "foo = a b c*")))
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
   check_match(exp, "a b a b a b x y", true, 3)
   check_match(exp, "a bx", false)
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
   check_match(exp, "c b b b b b cx", true, 2)			  -- !@# leftover correct?
   check_match(exp, "c b b b b b c x", true, 1, "c b b b b b c ") -- !@# trailing space?
   check_match(exp, "bc", false)
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
   check_match(exp, "a bc", true, 2, "a ")	    -- !@# trailing space?
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

subheading("Idempotency and impotence for cooked expressions")

function check_idem_etc_cooked(exp, input, expectation, leftover)
   check_match(exp, input, expectation, leftover)
   check_match("("..exp..")", input, expectation, leftover)	  -- idempotent
   check_match("{"..exp.."}", input, expectation, leftover)	  -- no-op
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
check_idem_etc_cooked('(c)+', "c c cx", true, 2)
check_idem_etc_cooked('(c)+', "", false)
check_idem_etc_cooked('(c)+', "ccccx", false)
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
check_idem_etc_raw('{(c)+}', "c c cx", true, 2)
check_idem_etc_raw('{(c)+}', "", false)
check_idem_etc_raw('{(c)+}', "ccccx", false)
check_idem_etc_raw('{(c){2,4}}', "c", false)
check_idem_etc_raw('{(c){2,4}}', "cc", false)
check_idem_etc_raw('{(c){2,4}}', "c c", true)
check_idem_etc_raw('{(c){2,4}}', "c c c c c c", true, 4)

-- return the test results in case this file is being called by another one which is collecting
-- up all the results:
return test.finish()
