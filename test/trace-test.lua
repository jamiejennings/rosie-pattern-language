---- -*- Mode: Lua; -*- 
----
---- trace-test.lua
----
---- © Copyright IBM Corporation 2016, 2017.
---- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
---- AUTHOR: Jamie A. Jennings
----

-- These tests are designed to run in the Rosie development environment, which is entered with: bin/rosie -D
assert(ROSIE_HOME, "ROSIE_HOME is not set?")
assert(type(rosie)=="table", "rosie package not loaded as 'rosie'?")
trace = rosie._env.trace
import = rosie._env.import
if not termcolor then
   import("termcolor")
end
if not test then
   test = import("test")
end

list = import("list")
check = test.check
heading = test.heading
subheading = test.subheading

e = false;
global_rplx = false;

lasttrace = "no trace set"

function check_eval(exp, input, expectation, expected_nextpos, expected_contents_list)
   local rplx, errs = e:compile(exp)
   if not rplx then
      error("this expression failed to compile: " .. exp)
   end
   local t = trace.expression(rplx, input)
   for k,v in pairs(t) do print(k,v); end
   check(( (expectation and t.match) or ((not expectation) and (not t.match)) ),
         "t.match was not as expected",
         1)
   if expectation then
      check(t.nextpos==expected_nextpos,
	    "t.nextpos was " .. tostring(t.nextpos) .. " but expected "
            .. tostring(expected_nextpos),
	    1)
   end
   
   -- check(ok, "failed call to eval: " .. tostring(m) .. "\nexp=" .. exp .. "\ninput=" .. input)
   -- if ok then
   --    check(expectation == (not (not m)), "expectation not met: " .. exp .. " " ..
   -- 	 ((m and "matched") or "did NOT match") .. " " .. input .. " ", 1)
   --    if type(expected_contents_list)=="table" then
   -- 	 local pos, all_met_flag, msg = 1, true, ""
   -- 	 for _, text in ipairs(expected_contents_list) do
   -- 	    local nextpos = localtrace:find(text, pos, true)	-- plain text matching flag is true
   -- 	    if nextpos then
   -- 	       pos = nextpos
   -- 	    else
   -- 	       msg = msg .. string.format("%q NOT found at/after position %d\n", text, pos)
   -- 	       all_met_flag = false
   -- 	    end
   -- 	 end -- for
   -- 	 check(all_met_flag, "expected content of trace not met:\n" .. msg, 1)
   --    end
   --    lasttrace = "\n\ncheck_eval('" .. exp .. "','" .. input .. "') returned this trace: \n" .. localtrace
   -- end -- if ok
end

print("+----------------------------------------------------------------------------------------+")
print("| Note that check_eval sets the global variable 'lasttrace', which can be easily printed |")
print("+----------------------------------------------------------------------------------------+")

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
t = e:lookup("a")
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
--check_eval('.', "xyz", true, 2)
--check_eval('~', "\t ", true, 3)
--check_eval('$', "", true, 1)

----------------------------------------------------------------------------------------
heading("Trace literals")
----------------------------------------------------------------------------------------
check_eval('"foo"', "foo", true, 4)
check_eval('"foo"', "foobar", true, 4)
check_eval('"foo"', "notfoo", false, nil)




--[===[

----------------------------------------------------------------------------------------
heading("Eval sequences")
----------------------------------------------------------------------------------------
check_eval('a b', "a b", true, {'SEQUENCE: (a ~ b)', '1...........LITERAL: "a"'})
check_eval('a b', "ab", false, {'SEQUENCE: (a ~ b)', '1...........LITERAL: "a"'})
check_eval('{a b}', "ab", true, {'SEQUENCE: (a b)', '1........LITERAL: "a"', '2........LITERAL: "b"'})
check_eval('({a b})', "ab", true, {'SEQUENCE: (a b)', '1........LITERAL: "a"', '2........LITERAL: "b"'})

----------------------------------------------------------------------------------------
heading("Eval alternation (choice)")
----------------------------------------------------------------------------------------
check_eval('a/b/c', "a", true, {'CHOICE: a / b / c',
				'1........LITERAL: "a"'})

check_eval('a/b/c', "d", false, {'CHOICE: a / b / c',
				 'FAILED'})

----------------------------------------------------------------------------------------
heading("Eval cooked groups")
----------------------------------------------------------------------------------------
check_eval('a b', "a b ", true, {'SEQUENCE: (a ~ b)',
				 '1...........LITERAL: "a"'})

check_eval('(a b)', "a b ", true, {'SEQUENCE: (a ~ b)',
				   '1...........LITERAL: "a"'})

check_eval('a b ~', "a bx", false, {'SEQUENCE: (a ~ b ~ ~)',
				  '1...........LITERAL: "a"',
				  'FAILED'})

check_eval('(a b)~', "a bx", false, {'SEQUENCE: (a ~ b ~ ~)',
				     '1.................LITERAL: "a"',
				     'FAILED'})
----------------------------------------------------------------------------------------
heading("Eval raw groups")
----------------------------------------------------------------------------------------
check_eval('{a b}', "a b ", false, {'SEQUENCE: (a b)',
				    '1........LITERAL: "a"',
				    'Matched',
				    '2........LITERAL: "b"',
				    'FAILED to match'})


check_eval('{a b}', "abx", true, {'SEQUENCE: (a b)',
				  '1........LITERAL: "a"',
				  'Matched',
				  '2........LITERAL: "b"',
				  'Matched'})


check_eval('({a b})~', "abx", false, {'SEQUENCE: (a b ~)',
				     '1..............LITERAL: "a"',
				     'Matched',
				     '2..............LITERAL: "b"',
				     'Matched',
				     'REFERENCE: ~',
				     'FAILED'})

----------------------------------------------------------------------------------------
heading("Eval look-ahead")
----------------------------------------------------------------------------------------
check_eval('a @b', "a b", true, {'SEQUENCE: (a ~ @b)',
				 '2.....PREDICATE: @b',
				 'Matched'})
check_eval('{a @b}', "ab", true, {'SEQUENCE: (a @b)'})

check_eval('{a @b}', "a", false, {'SEQUENCE: (a @b)',
				  '2.....PREDICATE: @b',
				  'FAILED'})

----------------------------------------------------------------------------------------
heading("Eval negative look-ahead")
----------------------------------------------------------------------------------------
check_eval('a !b', "ax", false, {'SEQUENCE: (a ~ !b)',
				 '1...........LITERAL: "a"',
				 'Matched',
				 'REFERENCE: ~',
				 'FAILED to match against input "x"'})

check_eval('{a !b}', "ax", true, {'SEQUENCE: (a !b)',
				  '3...........LITERAL: "b"',
				  'FAILED to match against input "x"'})

----------------------------------------------------------------------------------------
heading("Eval precedence and right association")
----------------------------------------------------------------------------------------
check_eval('a b / c', 'b c', false)
check_eval('a b / c', 'a c', true, {'SEQUENCE: (a ~ b / c)',
				    'Matched "a" (against input "a c")',
				    'REFERENCE: ~',
				    'Matched "c" (against input "c")',
				    '2...........LITERAL: "b"',
				    'First option failed.  Proceeding to alternative.',
				    '3...........LITERAL: "c"'})

check_eval('a b / c {3,3}', 'a ccc', true, {'SEQUENCE: (a ~ b / {c}{3,3})'})


check_eval('a b / c {3,3}', 'a cc', false, {'SEQUENCE: (a ~ b / {c}{3,3})',
					    'FAILED'})

print("\t ** Need more precedence and right association tests! **")

----------------------------------------------------------------------------------------
heading("Eval quantified expressions")
----------------------------------------------------------------------------------------
check_eval('a*', "", true, {'1..QUANTIFIED EXP (raw): {a}*',
			    'Matched'})

check_eval('a*', "aaaa", true, {'1..QUANTIFIED EXP (raw): {a}*',
				'Matched'})


check_eval('a+', "", false, {'1..QUANTIFIED EXP (raw): {a}+',
			     'FAILED'})

check_eval('a+', "a", true, {'1..QUANTIFIED EXP (raw): {a}+',
			     'Matched'})

check_eval('{a/b}+', "baaa", true, {'1..QUANTIFIED EXP (raw): {a / b}+',
				    'Matched "baaa"'})

check_eval('{a/b}{3,5}', "baaa", true, {'1..QUANTIFIED EXP (raw): {a / b}{3,5}',
					'Matched'})

check_eval('{a/b}{3,5}', "ba", false, {'1..QUANTIFIED EXP (raw): {a / b}{3,5}',
				       'FAILED'})


check_eval('(a*)', "", true, {'1..QUANTIFIED EXP (raw): {a}*',
			    'Matched'})

check_eval('(a*)', "aaaa", true, {'1..QUANTIFIED EXP (raw): {a}*',
				'Matched'})


check_eval('(a+)', "", false, {'1..QUANTIFIED EXP (raw): {a}+',
			     'FAILED'})

check_eval('(a+)', "a", true, {'1..QUANTIFIED EXP (raw): {a}+',
			     'Matched'})

check_eval('({a/b}+)', "baaa", true, {'1..QUANTIFIED EXP (raw): {a / b}+',
				    'Matched "baaa"'})

check_eval('({a/b}{3,5})', "baaa", true, {'1..QUANTIFIED EXP (raw): {a / b}{3,5}',
					'Matched'})

check_eval('({a/b}{3,5})', "ba", false, {'1..QUANTIFIED EXP (raw): {a / b}{3,5}',
				       'FAILED'})

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

check_eval('S', "aabb", true, {'1..GRAMMAR:',
			       'new_grammar',
			       'S = CAPTURE as S: {("a" B) / ("b" A) / ""}',
			       'A = CAPTURE as A: {("a" S) / ("b" A A)}',
			       'B = CAPTURE as B: {("b" S) / ("a" B B)}',
			       'end',
			       'Matched "aabb" (against input "aabb")'} )


--]===]

return test.finish()
