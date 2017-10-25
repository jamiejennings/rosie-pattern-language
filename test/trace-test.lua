---- -*- Mode: Lua; -*- 
----
---- trace-test.lua
----
---- © Copyright IBM Corporation 2016, 2017.
---- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
---- AUTHOR: Jamie A. Jennings
----

assert(TEST_HOME, "TEST_HOME is not set")

trace = rosie.env.trace
ast = rosie.env.ast

list = import("list")
check = test.check
heading = test.heading
subheading = test.subheading

e = false;
global_rplx = false;

lasttrace = "no trace set"

function check_trace(exp, input, expectation, expected_nextpos, expected_contents_list)
   local rplx, errs = e:compile(exp)
   if not rplx then
      error("this expression failed to compile: " .. exp, 2)
   end
   local t = trace.internal(rplx, input)
   lasttrace = t				    -- GLOBAL
   check(( (expectation and t.match) or ((not expectation) and (not t.match)) ),
      (expectation and
       "t.match was false but expected a match" or
       "t.match was true but expected no match"),
         1)
   if expectation then
      check(t.nextpos==expected_nextpos,
	    "t.nextpos was " .. tostring(t.nextpos) .. " but expected "
            .. tostring(expected_nextpos),
	    1)
   end
end

function printtrace()
   print(); for k,v in pairs(lasttrace) do print(k,v); end
   if lasttrace.subs then
      for i, sub in ipairs(lasttrace.subs) do
	 print("Sub " .. tostring(i) .. ": ")
	 for k,v in pairs(sub) do print(k,v); end
      end
      print("---")
   end
end

-- Examine the structure in the global lasttrace.
-- N.B.  By default, 'check_structure' looks only at the first level of structure in lasttrace.
-- To check the structure of lasttrace.subs[i], supply that as the first arg.
function check_structure(arg1, arg2, arg3)
   local tr, representation, subs_representation
   if type(arg1)=="string" then
      tr = lasttrace
      representation = arg1
      subs_representation = arg2
      assert(not arg3, "too many args to check_structure? arg3 is: " .. tostring(arg3))
   elseif type(arg1)=="table" then
      -- Assume arg1 is the trace we need to check
      tr = arg1
      representation = arg2
      subs_representation = arg3
   end
   assert(type(representation)=="string")
   assert(subs_representation==nil or (type(subs_representation)=="table"))
   
   local actual = ast.tostring(tr.ast)
   check(representation == actual,
	 "expected ast representation: " .. representation .. " but received: " .. actual,
	 1)
   if subs_representation then
      -- Caller expects all sub-matches to be a match iff expected_submatch is true
      local expected_submatch = subs_representation[1]
      table.remove(subs_representation, 1)
      local last = subs_representation[#subs_representation]
      if last==true or last==false then
	 -- Caller expects the last sub-match to be different from the rest, e.g. a match (true)
	 -- where the prior ones were non-matches, or false where the prior ones were matches.
	 -- From here on, we use last as a flag to indicate when the last sub-match is different. 
	 last = 999
	 table.remove(subs_representation, #subs_representation)
      else
	 -- Clear 'last' so we can use it as a flag to indicate whether the last sub-match is
	 -- expected to be different from expected_submatch
	 last = nil				   
      end
      local max = #subs_representation
      for i = 1, max do
	 local sub_rep = subs_representation[i]
	 if not tr.subs[i] then
	    check(false, "expected sub #" .. tostring(i) .. " but received no value", 1)
	 else
	    local actual = ast.tostring(tr.subs[i].ast)
	    check(sub_rep == actual,
		  "expected ast representation: " .. sub_rep .. " but received: " .. actual,
		  1)
	    -- Check the match to see if it jibes with what we expected
	    local m = tr.subs[i].match
	    if (last and (i==max)) then
	       expected_submatch = not expected_submatch
	    end
	    if expected_submatch then
	       check(m, "expected match success for " .. sub_rep, 1)
	    else
	       check(not m, "expected match failure for " .. sub_rep, 1)
	    end
	 end
      end -- for
   end -- if subs_representation
end

print("+-----------------------------------------------------------------------------------------+")
print("| Note that check_trace sets the global variable 'lasttrace', which can be easily printed |")
print("+-----------------------------------------------------------------------------------------+")

test.start(test.current_filename())

----------------------------------------------------------------------------------------
heading("Setting up")
----------------------------------------------------------------------------------------
check(type(rosie)=="table")
ok, e = pcall(rosie.engine.new, "trace test engine")
check(rosie.engine.is(e))
check(ok)

subheading("Setting up assignments")
ok = e:load('a = "a"  b = "b"  c = "c"  d = "d"')
check(ok)
t = e.env:lookup("a")
check(type(t)=="table")

ok = e:load('alias plain_old_alias = "p"')
check(ok)

ok = e:load('alias alias_to_plain_old_alias = plain_old_alias')
check(ok)

ok = e:load('alias alias_to_a = a')
check(ok)

ok = e:load('alternate_a = a')
check(ok)

ok = e:load('alternate_to_alias_to_a = alias_to_a')
check(ok)

ok = e:load('alias alias_to_alternate_to_alias_to_a = alias_to_a')
check(ok)

----------------------------------------------------------------------------------------
heading("Trace built-ins")
----------------------------------------------------------------------------------------
print("\tNeed tests for built-ins like ., $, and ~")
--check_trace('.', "xyz", true, 2)
--check_trace('~', "\t ", true, 3)
--check_trace('$', "", true, 1)

----------------------------------------------------------------------------------------
heading("Trace literals")
----------------------------------------------------------------------------------------
check_trace('"foo"', "foo", true, 4)
check(not lasttrace.subs)
check(ast.literal.is(lasttrace.ast))
check_trace('"foo"', "foobar", true, 4)
check(not lasttrace.subs)
check(ast.literal.is(lasttrace.ast))
check_trace('"foo"', "notfoo", false, nil)
check(not lasttrace.subs)
check(ast.literal.is(lasttrace.ast))

----------------------------------------------------------------------------------------
heading("Eval sequences")
----------------------------------------------------------------------------------------
check_trace('a b', "a b", true, 4)
check_structure("{a ~ b}", {true, "a", "~", "b"})

check_trace('a b', "ab", false, 3)
check_structure("{a ~ b}", {true, "a", "~", false})

check_trace('{a b}', "ab", true, 3)
check_structure("{a b}", {true, "a", "b"})

check_trace('({a b})', "ab", true, 3)
check_structure("{a b}", {true, "a", "b"})


----------------------------------------------------------------------------------------
heading("Eval alternation (choice)")
----------------------------------------------------------------------------------------
check_trace('a/b/c', "a", true, 2)
check_structure('{a / b / c}', {false, 'a', true})

check_trace('a/b/c', "c", true, 2)
check_structure('{a / b / c}', {false, 'a', 'b', 'c', true})

check_trace('a/b/c', "d", false, 1)
check_structure('{a / b / c}', {false, 'a', 'b', 'c'})

----------------------------------------------------------------------------------------
heading("Eval cooked groups")
----------------------------------------------------------------------------------------
check_trace('a b', "a b ", true, 4)		    -- leftover==1
check_structure('{a ~ b}', {true, 'a', '~', 'b'})

check_trace('(a b)', "a b ", true, 4)		    -- leftover==1
check_structure('{a ~ b}', {true, 'a', '~', 'b'})

check_trace('a b ~', "a bx", false, 1)
check_structure('{a ~ b ~ ~}', {true, 'a', '~', 'b', '~', false})

check_trace('(a b)~', "a bx", false, 1)
check_structure('{{a ~ b} ~ ~}', {true, '{a ~ b}', '~', false})


----------------------------------------------------------------------------------------
heading("Eval raw groups")
----------------------------------------------------------------------------------------


check_trace('{a b}', "a b ", false, 1)
check_structure('{a b}', {true, 'a', 'b', false})

check_trace('{a b}', "abx", true, 3)
check_structure('{a b}', {true, 'a', 'b'})

check_trace('({a b})~', "abx", false, 1)
check_structure('{{a b} ~ ~}', {true, '{a b}', '~', false})
check_structure(lasttrace.subs[1], '{a b}', {true, 'a', 'b'})


----------------------------------------------------------------------------------------
heading("Eval look-ahead")
----------------------------------------------------------------------------------------
check_trace('a >b', "a b", true, 3)
check_structure('{a ~ >b}', {true, 'a', '~', '>b'})

check_trace('{a >b}', "ab", true, 2)
check_structure('{a >b}', {true, 'a', '>b'})

check_trace('{a >b}', "a", false, 1)
check_structure('{a >b}', {true, 'a', '>b', false})

----------------------------------------------------------------------------------------
heading("Eval negative look-ahead")
----------------------------------------------------------------------------------------
check_trace('a !b', "ax", false, 1)
check_structure('{a ~ !b}', {true, 'a', '~', false})

check_trace('{a !b}', "ax", true, 2)
check_structure('{a !b}', {true, 'a', '!b'})
check_structure(lasttrace.subs[2], '!b', {false, 'b'})


----------------------------------------------------------------------------------------
heading("Eval precedence and right association")
----------------------------------------------------------------------------------------
check_trace('a b / c', 'b c', false, 1)
check_structure('{a ~ {b / c}}', {true, 'a', false})

check_trace('a b / c', 'a c', true, 4)
check_structure('{a ~ {b / c}}', {true, 'a', '~', '{b / c}'})
check_structure(lasttrace.subs[3], '{b / c}', {false, 'b', 'c', true})

check_trace('a b / c{3,3}', 'a ccc', true, 6)
check_structure('{a ~ {b / {c c c}}}', {true, 'a', '~', '{b / {c c c}}'})

check_trace('a b / c{3,3}', 'a cc', false, 1)
check_structure('{a ~ {b / {c c c}}}', {true, 'a', '~', '{b / {c c c}}', false})
check_structure(lasttrace.subs[3], '{b / {c c c}}', {false, 'b', '{c c c}'})
check_structure(lasttrace.subs[3].subs[2], '{c c c}', {true, 'c', 'c', 'c', false})

print("\n\t ** Need more precedence and right association tests! **")


----------------------------------------------------------------------------------------
heading("Eval quantified expressions")
----------------------------------------------------------------------------------------
check_trace('a*', "", true, 1)
check_structure('{a}*', {true, 'a', false})

check_trace('a*', "aaaa", true, 5)
check_structure('{a}*', {true, 'a', 'a', 'a', 'a'})

check_trace('a+', "", false, 1)
check_structure('{a}+', {false, 'a'})

check_trace('a+', "a", true, 2)
check_structure('{a}+', {true, 'a', 'a', false})

check_trace('{a/b}+', "baaa", true, 5)
check_structure('{a / b}+', {true, '{a / b}', '{a / b}', '{a / b}', '{a / b}'})

check_trace('{a/b}{3,5}', "baaa", true, 5)
check_structure('{{a / b} {a / b} {a / b} {a / b}{,2}}', {true, '{a / b}', '{a / b}', '{a / b}', '{a / b}{,2}'})

check_trace('{a/b}{3,5}', "ba", false, 1)
check_structure('{{a / b} {a / b} {a / b} {a / b}{,2}}', {true, '{a / b}', '{a / b}', '{a / b}', false})

check_trace('(a*)', "", true, 1)
check_structure('{{a}*}', {true, '{a}*'})

check_trace('(a*)', "aaaa", true, 5)
check_structure('{{a}*}', {true, '{a}*'})

check_trace('(a+)', "", false, 1)
check_structure('{{a}+}', {false, '{a}+'})

check_trace('(a+)', "a", true, 2)
check_structure('{{a}+}', {true, '{a}+'})

check_trace('({a/b}+)', "baaa", true, 5)
--check_structure('{a / b}+', {true, '{a / b}', '{a / b}', '{a / b}', '{a / b}', '{a / b}', false})
check_structure('{{a / b}+}', {true, '{a / b}+'})

check_trace('({a/b}{3,5})', "baaa", true, 5)
check_structure('{{{a / b} {a / b} {a / b} {a / b}{,2}}}', {true, '{{a / b} {a / b} {a / b} {a / b}{,2}}'})

check_trace('({a/b}{3,5})', "baaabXYZ", true, 6)
check_structure('{{{a / b} {a / b} {a / b} {a / b}{,2}}}', {true, '{{a / b} {a / b} {a / b} {a / b}{,2}}'})

check_trace('({a/b}{3,5})', "baaabaYZ", true, 6)
check_structure('{{{a / b} {a / b} {a / b} {a / b}{,2}}}', {true, '{{a / b} {a / b} {a / b} {a / b}{,2}}'})

check_trace('({a/b}{3,5})', "ba", false, 1)
check_structure('{{{a / b} {a / b} {a / b} {a / b}{,2}}}', {false, '{{a / b} {a / b} {a / b} {a / b}{,2}}'})

----------------------------------------------------------------------------------------
heading("Eval grammar")
----------------------------------------------------------------------------------------

-- balanced strings of a's and b's
g = [[grammar
  S = {"a" B} / {"b" A} / "" 
  A = {"a" S} / {"b" A A}
  B = {"b" S} / {"a" B B}
end]]

ok, msg = e:load(g)
check(ok)
check(not msg)

check_trace('S', "aabb", true, 5)
-- {'1..GRAMMAR:',
-- 			       'new_grammar',
-- 			       'S = CAPTURE as S: {("a" B) / ("b" A) / ""}',
-- 			       'A = CAPTURE as A: {("a" S) / ("b" A A)}',
-- 			       'B = CAPTURE as B: {("b" S) / ("a" B B)}',
-- 			       'end',
-- 			       'Matched "aabb" (against input "aabb")'} )

----------------------------------------------------------------------------------------
heading("Eval char sets")

subheading("Simple charsets")

ok, msg = e:load("not_a = [^a]")
check(ok)
check_trace('not_a', "abc", false, 000)		    --nextpos does not matter for false
check_trace('not_a', "a", false, 000)		    --nextpos does not matter for false
check_trace('not_a', "x", true, 2)		    --nextpos is 2 after matching "x"

ok, msg = e:load("not_a = [^[a]]")
check(ok)

check_trace('not_a', "abc", false, 000)		    --nextpos does not matter for false
check_trace('not_a', "a", false, 000)		    --nextpos does not matter for false
check_trace('not_a', "x", true, 2)		    --nextpos is 2 after matching "x"

ok, msg = e:load("foo = [^[a][b][c]]")
check(ok)

check_trace('foo', "x", true, 2)
check_trace('foo', "a", false)
check_trace('foo', "b", false)
check_trace('foo', "c", false)

ok, msg = e:load("foo = [^[a][b][^c]]")
check(ok)

check_trace('foo', "x", false)
check_trace('foo', "a", false)
check_trace('foo', "b", false)
check_trace('foo', "c", true, 2)

ok, msg = e:load("foo = [^[^a][b][^c]]")
check(ok)

check_trace('foo', "x", false)
check_trace('foo', "a", false, 2)
check_trace('foo', "b", false)
check_trace('foo', "c", false, 2)

ok, msg = e:load("foo = [^[^a][b-z]]")
check(ok)

check_trace('foo', "x", false)
check_trace('foo', "a", true, 2)
check_trace('foo', "b", false)
check_trace('foo', "c", false, 2)

ok, msg = e:load("foo = [[^a][a-b]]")
check(ok)

check_trace('foo', "x", true, 2)
check_trace('foo', "a", true, 2)
check_trace('foo', "b", true, 2)
check_trace('foo', "c", true, 2)

ok, msg = e:load("foo = [[^b-c]&[a-d]]")
check(ok)

check_trace('foo', "x", false)
check_trace('foo', "a", true, 2)
check_trace('foo', "b", false)
check_trace('foo', "c", false)
check_trace('foo', "d", true, 2)


return test.finish()
