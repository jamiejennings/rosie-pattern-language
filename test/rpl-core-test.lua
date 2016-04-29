---- -*- Mode: Lua; -*- 
----
---- test-rpl-core.lua
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
   local ok, msg = api.configure_engine(eid, json.encode{expression=exp, encoder=false})
   if not ok then error("Configuration error: " .. msg); end
end

function check_match(exp, input, expectation, expected_leftover, expected_text)
   expected_leftover = expected_leftover or 0
   set_expression(exp)
   local ok, retvals_js = api.match(eid, input)
   check(ok, "failed call to api.match")
   local retvals = json.decode(retvals_js)
   local m, leftover = retvals[1], retvals[2]
   check(expectation == (not (not m)), "expectation not met: " .. exp .. " " ..
	 ((m and "matched") or "did NOT match") .. " '" .. input .. "'", 1)
   local fmt = "expected leftover matching %s against '%s' was %d but received %d"
   if expectation then
      check(leftover==expected_leftover,
	    string.format(fmt, exp, input, expected_leftover, leftover), 1)
      if expected_text and m then
	 local name, match = next(m)
	 local text = match.text
	 local fmt = "expected text matching %s against '%s' was '%s' but received '%s'"
	 check(expected_text==text,
	       string.format(fmt, exp, input, expected_text, text), 1)
      end
   end
end
      
test.start()

----------------------------------------------------------------------------------------
heading("Setting up")
----------------------------------------------------------------------------------------
api = require "api"

check(type(api)=="table")
check(api.API_VERSION)
check(type(api.API_VERSION=="string"))

check(type(api.new_engine)=="function")
ok, eid_js = api.new_engine("hello")
check(ok)
eid = json.decode(eid_js)
check(type(eid)=="string")

subheading("Setting up assignments")
ok, msg = api.load_string(eid, 'a = "a"  b = "b"  c = "c"  d = "d"')
check(ok)
ok, msg = api.get_binding(eid, "a")
check(ok)

----------------------------------------------------------------------------------------
heading("Literals")
----------------------------------------------------------------------------------------
subheading("Built-ins")
check_match(".", "a", true)
check_match(".", "abcd", false)
check_match("(.)", "abcd", false)
check_match("{.}", "abcd", true, 3, "a")
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
check_match('...', "H e llo", false)
check_match('(...)', "H e llo", false)
check_match('(...)', "H e l lo", true, 2)
check_match('{...}', "H e llo", true, 4, "H e")
check_match('.*.', "Hello", false)
check_match('"hi" "there"', "hi there", true)
check_match('("hi" "there")', "hi there", true)
check_match('{"hi" "there"}', "hi there", false)
check_match('"hi" "there"', "hi there lovely", true, 6)
check_match('"hi" "there"', "hi\nthere", true)
check_match('"hi" "there"', "hi\n\t\t    there ", true, 0)
check_match('"hi" "there"', "hithere", false)

----------------------------------------------------------------------------------------
heading("Alternation (choice)")
----------------------------------------------------------------------------------------
check_match('a / b', "", false)
check_match('a / b', "x", false)
check_match('a / b', "a", true, 0, "a")
check_match('a / b', "ab", false)
check_match('a / b', "a b", true, 1, "a")
check_match('a / b', "ba", false)
check_match('a / b', "b a", true, 1, "b")
check_match('a / b', "b b", true, 1, "b")
check_match('a / b', "b", true, 0, "b")
check_match('a / b / c', "a", true, 0, "a")
check_match('a / b / c', "b ", true, 0, "b")
check_match('{a / b / c}', "b ", true, 1, "b")
check_match('a / b / c', "c a", true, 1, "c")
check_match('(a / b / c)', "c a", true, 1, "c")
check_match('{a / b / c}', "c a", true, 2, "c")

----------------------------------------------------------------------------------------
heading("Cooked groups")
----------------------------------------------------------------------------------------
check_match('a b c', "a b c", true, 0, "a b c")
check_match('(a b c)', "a b c", true, 0, "a b c")
check_match('a (b c)', "a b c", true, 0, "a b c")
check_match('a / (b c)', "a b c", true, 3, "a")
check_match('a / (b c)', "b c a", true, 1, "b c")
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
check_match('a / {b c}', "a b c", true, 3, "a")
check_match('a / {b c}', "b c a", false)
check_match('a / {b c}', "b c", false)
check_match('a / {b c}', " bc", false)
check_match('a / {b c}', "bc", true, 0, "bc")
check_match('{a / b} c', "a b c", false)
check_match('{a / b} c', "b c a", true, 1, "b c")
check_match('{a / b} c', "b c", true, 0, "b c")
check_match('{a / b} c', " bc", false)

----------------------------------------------------------------------------------------
heading("Look-ahead")
----------------------------------------------------------------------------------------


----------------------------------------------------------------------------------------
heading("Negative look-ahead")
----------------------------------------------------------------------------------------

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
check_match('a / b c', 'ac', false)

check_match('a / b c', 'a c', true, 1, "a")
-- Warning: did not match entire input line
check_match('a / b c', 'bc', false)

check_match('a / b c', 'b c', true, 0, "b c")
-- [test: [1: b c, 2: [b: [1: b]], 3: [c: [1: c]]]]

subheading("Testing a b / c d, which is equivalent to a (b / (c d))")
check_match('a b / c d', 'a b', true, 0, "a b")
-- [test: [1: a b, 2: [a: [1: a]], 3: [b: [1: b]]]]
check_match('a b / c d', 'a b d', true, 1, "a b")
-- Warning: did not match entire input line
check_match('a b / c d', 'a c d', true, 0, "a c d")

subheading("Testing ! a b c, which is equivalent to !a (b c)")
check_match('! a b c', 'a b c', false)
check_match('! a b c', 'x', false)
check_match('! a b c', 'x b c', false)
check_match('! a b c', 'b c', true, 0, "b c")

subheading("Testing a b c*, which is equivalent to a b (c*)")
check_match('a b c *', 'a b c', true, 0, "a b c")
check_match('a b c *', 'a b c a b c', true, 5, "a b c")
check_match('a b c *', 'a b c c c', true, 3, "a b c")
check_match('a b c *', 'a b ccc', true, 0, "a b ccc")

subheading("Testing a b (c)*, for contrast with a b c*")
-- Note that c* is raw whereas (c)* is cooked
check_match('a b (c)*', 'a b ccc', false)
check_match('(a b (c)*)', 'a b ccc', false)
check_match('{(a b (c)*)}', 'a b ccc', true, 2, "a b c")
check_match('a b (c)*', 'a b c c c', true, 0, "a b c c c")
check_match('(a b (c)*)', 'a b c c c', true, 0, "a b c c c")
check_match('(a b (c)*)', 'a b c c c x', true, 1, "a b c c c")
check_match('(a b (c)*)', 'a b c c cx', false)

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
check_match('!a+', ' b', true, 1, "")		    -- note boundary added at top level
check_match('(!a+)', ' b', true, 1, "")		    -- note boundary added at top level
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
check_match('a{1,2}', 'aaa', false)
check_match('(a{1,2})', 'aaa', false)
check_match('{a{1,2}}', 'aaa', true, 1, "aa")
check_match('a{1,2}', 'x', false)

subheading("Testing a{0,1} against a, aa, and x")
check_match('a{0,1}', 'a', true, 0, "a")
check_match('a{0,1}', 'aa', false)
check_match('(a{0,1})', 'aa', false)
check_match('{a{0,1}}', 'aa', true, 1, "a")
check_match('a{0,1}', 'x', true, 1, "")

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
check_match('(a)*', 'aa', false)
check_match('{a}*', 'aax', false)
check_match('{{a}*}', 'aa ', true, 1, "aa")
check_match('{(a)*}', 'aax', true, 2, "a")	    -- odd looking, but correct
check_match('(a)*', 'a a', true, 0, "a a")
check_match('(a)*', 'a ax', false)
check_match('(a)*', 'a a   ', true, 0, "a a")
check_match('((a)*)', 'a a   ', true, 0, "a a")
check_match('{(a)*}', 'a a   ', true, 3, "a a")
check_match('(a)*', ' a a   ', true, 6, "")	    -- note boundary added at top level
check_match('{(a)*}', ' a a   ', true, 7, "")

subheading("Explicit boundary pattern")
check_match('~(a)*', ' a a   ', true, 0, " a a")
check_match('(~(a)*)', ' a a   ', true, 0, " a a")
ok, msg = api.load_string(eid, "token = { ![:space:] . {!~ .}* }")
check(ok)
check_match('token', 'The quick, brown fox.\nSentence fragment!!  ', true, 39, "The")
check_match('token token token', 'The quick, brown fox.\nSentence fragment!!  ', true, 32, "The quick,")
check_match('token{4,}', 'The quick, brown fox.\nSentence fragment!!', false)
check_match('(token){4,}', 'The quick, brown fox.\nSentence fragment!!', true, 0)
-- The 4th token is a comma in the following match:
check_match('(token){4,4}', 'The quick, brown fox.\nSentence fragment!!  ', true, 26)
check_match('token*', 'The quick, brown fox.\nSentence fragment!!  ', true, 39, "The")
check_match('{token}*', 'The quick, brown fox.\nSentence fragment!!  ', true, 39, "The")
check_match('({token}*)', 'The quick, brown fox.\nSentence fragment!!  ', true, 39, "The")
check_match('(token)*', 'The quick, brown fox.\nSentence fragment!!  ', true, 0)
check_match('((token)*)', 'The quick, brown fox.\nSentence fragment!!  ', true, 0)
check_match('{(token)*}', 'The quick, brown fox.\nSentence fragment!!  ', true, 2)

check_match('(token)*', '\tThe quick, brown fox.\nSentence fragment!!  ', true, 43, "")
check_match('{(token)*}', '\tThe quick, brown fox.\nSentence fragment!!  ', true, 44, "")
check_match('~(token)*', '\tThe quick, brown fox.\nSentence fragment!!  ', true, 0)
check_match('(~token)*', '\tThe quick, brown fox.\nSentence fragment!!  ', true, 0)
check_match('(~token~)*', '\tThe quick, brown fox.\nSentence fragment!!  ', true, 0)

subheading("Boundary idempotence")
check_match('~~~~~~', '     V', true, 1, "     ")
check_match('~~~~~~', 'V', true, 1, "")		    -- idempotent
check_match('(~~~~~~)', '     V', true, 1, "     ")
check_match('(~~~~~~)', 'V', true, 1, "")	    -- idempotent
check_match('{~~~~~~}', '     V', true, 1, "     ")
check_match('{~~~~~~}', 'V', true, 1, "")	    -- idempotent

check_match('~', 'X', true, 1, "")
check_match('~', '', true, 0, "")
check_match('"X"~', 'X', true, 0, "X")
check_match('"X"~~~~', 'X', true, 0, "X")	    -- idempotent

subheading("Alternation (basic)")
check_match('{ a / b }', 'ax', true, 1, "a")
check_match('a / b', 'ax', false)
check_match('a / b', 'a x', true, 1)
check_match('a / b', 'a', true)
check_match('(a / b)', 'ax', false)
check_match('(a / b)', 'a x', true, 1, "a")
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
check_match('b a / b', 'b a   x', true, 1)

check_match('b (a / b)', 'b', false)
check_match('b (a / b)', 'b a', true)
check_match('b (a / b)', 'b b', true)
check_match('b (a / b)', 'b a   x', true, 1)

check_match('b {a / b}', 'b', false)
check_match('b {a / b}', 'b a', true)
check_match('b {a / b}', 'b b', true)
check_match('b {a / b}', 'b a   x', true, 1)

check_match('(b a / b)', 'b', false)
check_match('(b a / b)', 'b a', true)
check_match('(b a / b)', 'b b', true)
check_match('(b a / b)', 'b a   x', true, 1)

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

check_match('{b (a / b)}', 'bax', true, 1)	    -- this is key: no top-level boundary added
check_match('({b (a / b)})', 'bax', false)	    -- this is key: top-level boundary added

check_match('{b (a)}', 'bax', true, 1)
check_match('({b (a)})', 'bax', false)
check_match('{b (a)}', 'ba x', true, 2)

----------------------------------------------------------------------------------------
test.heading("Quantified expressions")
----------------------------------------------------------------------------------------
subheading("Kleene star")
check_match('a*', '', true)
check_match('a*', 'a', true)
check_match('a*', 'aaaaaa', true)
check_match('a*', 'aaaaaa ', true, 0)
check_match('{a*}', 'aaaaaa ', true, 1)		    -- !@# let's not capture the trailing boundary
check_match('a*', 'x', true, 1, '')
check_match('{a}*', '', true)
check_match('{a}*', 'a', true)
check_match('{a}*', 'aaaaaa', true)
check_match('{a}*', 'aaaaaa ', true, 0)
check_match('{{a}*}', 'aaaaaa ', true, 1)
check_match('{a}*', 'x', true, 1, '')
check_match('(a)*', '', true)
check_match('(a)*', 'a', true)
check_match('(a)*', 'aa', false)
check_match('(a)*', 'a a a a', true)
check_match('(a)*', 'a a a a    ', true)
check_match('((a)*)', 'a a a a    ', true)
check_match('{(a)*}', 'a a a a    ', true, 4)	    -- 4 spaces leftover
check_match('(a)*', 'a a a a x', true, 1)
check_match('((a)*)', 'a a a a x', true, 1)
check_match('{(a)*}', 'a a a a x', true, 2)
check_match('(a)*', 'x', true, 1, '')

subheading("Plus")
check_match('a+', '', false)
check_match('a+', 'a', true)
check_match('a+', 'aaaaaa', true)
check_match('a+', 'aaaaaa ', true, 0)
check_match('{a+}', 'aaaaaa ', true, 1)
check_match('a+', 'x ', false)
check_match('{a}+', '', false)
check_match('{a}+', 'a', true)
check_match('{a}+', 'aaaaaa', true)
check_match('{a}+', 'aaaaaa ', true, 0)
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
check_match('a?', 'aaaaaa', false)
check_match('a?', 'a ', true, 0, 'a')
check_match('{a}?', '', true, 0, '')
check_match('{a}?', 'a', true, 0, 'a')
check_match('{a}?', 'aaaaaa', false)
check_match('{{a}?}', 'aaaaaa', true, 5, 'a')
check_match('{a}?', 'a ', true, 0, 'a')
check_match('(a)?', '', true, 0, '')
check_match('(a)?', 'a', true, 0, 'a')
check_match('(a)?', 'aa', false)
check_match('((a)?)', 'aa', false)
check_match('{(a)?}', 'aa', true, 1, 'a')
check_match('(a)?', 'a a', true, 1, 'a')
check_match('((a)?)', 'a a', true, 1, 'a')
check_match('{(a)?}', 'a a', true, 2, 'a')
check_match('(a)?', 'ax', false)
check_match('((a)?)', 'ax', false)
check_match('{(a)?}', 'ax', true, 1, 'a')
check_match('(a)?', 'x', true, 1, '')
check_match('((a)?)', 'x', true, 1, '')
check_match('{(a)?}', 'x', true, 1, '')

subheading("Range with min (cooked)")
check_match('c{0,}', '', true)
check_match('c{0,}', 'x', true, 1)		    -- because start of input is a boundary
check_match('c{0,}', 'c', true)
check_match('c{0,}', 'cx', false)
check_match('c{0,}', 'c x', true, 1)
check_match('c{0,}', ' x', true, 1)
check_match('c{0,}', '!', true, 1)
check_match('c{0,}', 'cccccccccc x', true, 1)

check_match('c{1,}', '', false)
check_match('c{1,}', 'x', false)
check_match('c{1,}', 'c', true)
check_match('c{1,}', 'cx', false)
check_match('c{1,}', 'c x', true, 1)
check_match('c{1,}', ' x', false)
check_match('c{1,}', 'c!', true, 1)
check_match('c{1,}', 'cccccccccc#x', true, 2)

check_match('c{2,}', '', false)
check_match('c{2,}', 'x', false)
check_match('c{2,}', 'c', false)
check_match('c{2,}', 'ccx', false)
check_match('c{2,}', 'cc x', true, 1)
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
check_match('c{,0}', 'cx', false)
check_match('c{,0}', 'c x', true, 1)
check_match('c{,0}', ' x', true, 1)
check_match('c{,0}', '!', true, 1)
check_match('c{,0}', 'cccccccccc x', true, 1)

check_match('c{,1}', '', true)
check_match('c{,1}', 'x', true, 1)
check_match('c{,1}', 'c', true)
check_match('c{,1}', 'cx', false)
check_match('c{,1}', 'c x', true, 1)
check_match('c{,1}', ' x', true, 1)
check_match('c{,1}', 'c!', true, 1)
check_match('c{,1}', 'cccccccccc#x', false)

check_match('c{,2}', '', true)
check_match('c{,2}', 'x', true, 1)
check_match('c{,2}', 'c', true)
check_match('c{,2}', 'ccx', false)
check_match('c{,2}', 'cc x', true, 1)
check_match('c{,2}', ' x', true, 1)
check_match('c{,2}', 'cc!', true, 1)
check_match('c{,2}', 'cccccccccc#x', false)

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
check_match('a{3,5}', 'aaaaaa', false)
check_match('(a{3,5})', 'aaaaaa', false)
check_match('{a{3,5}}', 'aaaaaa', true, 1)
check_match('a{3,5}', 'a a a', false)

subheading("Range with min, max (cooked)")
check_match('b{2,4}', '', false)
check_match('b{2,4}', 'x', false)
check_match('b{2,4}', 'b', false)
check_match('b{2,4}', 'bb', true)
check_match('b{2,4}', 'bbb', true)
check_match('b{2,4}', 'bbbb', true)

-- cooked mode, so looking for a boundary after the b's
check_match('b{2,4}', 'bbbbb', false)
check_match('b{2,4}', 'bbxyz', false)
check_match('b{2,4}', 'bbbxyz', false)
check_match('b{2,4}', 'bbbbxyz', false)
check_match('b{2,4}', 'bbbbbxyz', false)
check_match('b{2,4}', 'b b', false)
check_match('b{2,4}', 'bb b', true, 1, 'bb')
check_match('b{2,4}', 'bbb b', true, 1, 'bbb')
check_match('b{2,4}', 'bbbb b', true, 1, 'bbbb')

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

check_match('({(a b) (c d)})', 'a bc dx', false)
check_match('((a b) (c d))', 'a b c dx', false)
check_match('(a b) (c d)', 'a b c dx', false)
check_match('{a b} {c d}', 'ab cdx', false)

test.finish()

