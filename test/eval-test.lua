---- -*- Mode: Lua; -*- 
----
---- eval-test.lua
----
---- (c) 2016, Jamie A. Jennings
----

test = require "test-functions"
eval = require "eval"

check = test.check
heading = test.heading
subheading = test.subheading

e = false;

function set_expression(exp)
   local ok, msg = lapi.configure_engine(e, {expression=exp, encode="json"})
   if not ok then error("Configuration error: " .. msg); end
end

function check_match(...) error("Called check_match accidentally"); end

trace = "no trace set"

function check_eval(exp, input, expectation, expected_contents_list)
   set_expression(exp)
   local ok, m, leftover, trace = pcall(lapi.eval, e, input)
   local localtrace = eval.trace_tostring(trace)
   check(ok, "failed call to lapi.eval: " .. tostring(m))
   if ok then
      check(expectation == (not (not m)), "expectation not met: " .. exp .. " " ..
	 ((m and "matched") or "did NOT match") .. " " .. input .. " ", 1)
      if expected_contents_list then
	 local pos, all_met_flag, msg = 1, true, ""
	 for _, text in ipairs(expected_contents_list) do
	    local nextpos = localtrace:find(text, pos, true)	-- plain text matching flag is true
	    if nextpos then
	       pos = nextpos
	    else
	       msg = msg .. string.format("%q NOT found at/after position %d\n", text, pos)
	       all_met_flag = false
	    end
	 end -- for
	 check(all_met_flag, "expected content of trace not met:\n" .. msg, 1)
      end
      trace = "\n\ncheck_eval('" .. exp .. "','" .. input .. "') returned this trace: \n" .. localtrace
   end -- if ok
end

print("+------------------------------------------------------------------------------------+")
print("| Note that check_eval sets the global variable 'trace', which can be easily printed |")
print("+------------------------------------------------------------------------------------+")

test.start(test.current_filename())

----------------------------------------------------------------------------------------
heading("Setting up")
----------------------------------------------------------------------------------------
check(type(lapi)=="table")
check(type(lapi.new_engine)=="function")
e, config_ok, msg = lapi.new_engine({name="eval test"})
check(engine.is(e))
check(config_ok)

subheading("Setting up assignments")
t1, t2 = lapi.load_string(e, 'a = "a"  b = "b"  c = "c"  d = "d"')
check(type(t1)=="table")
if t2 then check(type(t2)=="table"); end
t = lapi.get_environment(e, "a")
check(type(t)=="table")

ok, msg = pcall(lapi.load_string, e, 'alias plain_old_alias = "p"')
check(ok)

ok, msg = pcall(lapi.load_string, e, 'alias alias_to_plain_old_alias = plain_old_alias')
check(ok)

ok, msg = pcall(lapi.load_string, e, 'alias alias_to_a = a')
check(ok)

ok, msg = pcall(lapi.load_string, e, 'alternate_a = a')
check(ok)

ok, msg = pcall(lapi.load_string, e, 'alternate_to_alias_to_a = alias_to_a')
check(ok)

ok, msg = pcall(lapi.load_string, e, 'alias alias_to_alternate_to_alias_to_a = alias_to_a')
check(ok)

----------------------------------------------------------------------------------------
heading("Eval built-ins")
----------------------------------------------------------------------------------------
print("\tNeed tests for built-ins like ., $, and ~")

----------------------------------------------------------------------------------------
heading("Eval literals")
----------------------------------------------------------------------------------------
check_eval('"foo"', "foo", true, {'LITERAL: "foo"', 'match from 1 to 4 (length=3)'})
check_eval('"foo"', "foobar", true, {'LITERAL: "foo"', 'match from 1 to 4 (length=3)'})
check_eval('"foo"', "notfoo", false, {'LITERAL: "foo"', 'fail at 1'})

----------------------------------------------------------------------------------------
heading("Eval sequences")
----------------------------------------------------------------------------------------
check_eval('a b', "a b", true, {'SEQUENCE: (a ~ b)',
				'match from 1 to 4 (length=3)',
				'SEQUENCE: (a ~)',
				'match from 1 to 3 (length=2)',
				'REFERENCE: a',
				'match from 1 to 2 (length=1)',
				'LITERAL: "a"',
				'match from 1 to 2 (length=1)',
				'REFERENCE: ~',
				'match from 2 to 3 (length=1)',
				'REFERENCE: b',
				'match from 3 to 4 (length=1)',
				'LITERAL: "b"',
				'match from 3 to 4 (length=1)'})
check_eval('a b', "ab", false, {'SEQUENCE: (a ~ b)',
				'fail at 1',
				'SEQUENCE: (a ~)',
				'fail at 1',
				'REFERENCE: a',
				'match from 1 to 2 (length=1)',
				'LITERAL: "a"',
				'match from 1 to 2 (length=1)',
				'REFERENCE: ~',
				'fail at 2'})
check_eval('{a b}', "ab", true, {'SEQUENCE: (a b)',
				 'match from 1 to 3 (length=2)',
				 'REFERENCE: a',
				 'match from 1 to 2 (length=1)',
				 'LITERAL: "a"',
				 'match from 1 to 2 (length=1)',
				 'REFERENCE: b',
				 'match from 2 to 3 (length=1)',
				 'LITERAL: "b"',
				 'match from 2 to 3 (length=1)'})
check_eval('({a b})', "ab", true, {'SEQUENCE: (a b)',
				   'match from 1 to 3 (length=2)',
				   'REFERENCE: a',
				   'match from 1 to 2 (length=1)',
				   'LITERAL: "a"',
				   'match from 1 to 2 (length=1)',
				   'REFERENCE: b',
				   'match from 2 to 3 (length=1)',
				   'LITERAL: "b"',
				   'match from 2 to 3 (length=1)'})

----------------------------------------------------------------------------------------
heading("Eval alternation (choice)")
----------------------------------------------------------------------------------------
check_eval('a/b/c', "a", true, {'CHOICE: a / b / c',
				'match from 1 to 2 (length=1)',
				'REFERENCE: a',
				'match from 1 to 2 (length=1)',
				'LITERAL: "a"',
				'match from 1 to 2 (length=1)'})

check_eval('a/b/c', "d", false, {'CHOICE: a / b / c',
				 'fail at 1',
				 'REFERENCE: a',
				 'fail at 1',
				 'LITERAL: "a"',
				 'fail at 1',
				 'CHOICE: b / c',
				 'fail at 1',
				 'REFERENCE: b',
				 'fail at 1',
				 'LITERAL: "b"',
				 'fail at 1',
				 'REFERENCE: c',
				 'fail at 1',
				 'LITERAL: "c"',
				 'fail at 1'})

----------------------------------------------------------------------------------------
heading("Eval cooked groups")
----------------------------------------------------------------------------------------
check_eval('a b', "a b ", true, {'SEQUENCE: (a ~ b)',
				 'match from 1 to 4 (length=3)',
				 'SEQUENCE: (a ~)',
				 'match from 1 to 3 (length=2)',
				 'REFERENCE: a',
				 'match from 1 to 2 (length=1)',
				 'LITERAL: "a"',
				 'match from 1 to 2 (length=1)',
				 'REFERENCE: ~',
				 'match from 2 to 3 (length=1)',
				 'REFERENCE: b',
				 'match from 3 to 4 (length=1)',
				 'LITERAL: "b"',
				 'match from 3 to 4 (length=1)'})

check_eval('(a b)', "a b ", true, {'SEQUENCE: (a ~ b)',
				   'match from 1 to 4 (length=3)',
				   'SEQUENCE: (a ~)',
				   'match from 1 to 3 (length=2)',
				   'REFERENCE: a',
				   'match from 1 to 2 (length=1)',
				   'LITERAL: "a"',
				   'match from 1 to 2 (length=1)',
				   'REFERENCE: ~',
				   'match from 2 to 3 (length=1)',
				   'REFERENCE: b',
				   'match from 3 to 4 (length=1)',
				   'LITERAL: "b"',
				   'match from 3 to 4 (length=1)'})

check_eval('a b ~', "a bx", false, {'SEQUENCE: (a ~ b ~ ~)',
				    'fail at 1',
				    'SEQUENCE: (a ~)',
				    'match from 1 to 3 (length=2)',
				    'REFERENCE: a',
				    'match from 1 to 2 (length=1)',
				    'LITERAL: "a"',
				    'match from 1 to 2 (length=1)',
				    'REFERENCE: ~',
				    'match from 2 to 3 (length=1)',
				    'SEQUENCE: (b ~ ~)',
				    'fail at 3',
				    'SEQUENCE: (b ~)',
				    'fail at 3',
				    'REFERENCE: b',
				    'match from 3 to 4 (length=1)',
				    'LITERAL: "b"',
				    'match from 3 to 4 (length=1)',
				    'REFERENCE: ~',
				    'fail at 4'})

check_eval('(a b)~', "a bx", false, {'SEQUENCE: (a ~ b ~ ~)',
				     'fail at 1',
				     'SEQUENCE: (a ~ b ~)',
				     'fail at 1',
				     'SEQUENCE: (a ~ b)',
				     'match from 1 to 4 (length=3)',
				     'SEQUENCE: (a ~)',
				     'match from 1 to 3 (length=2)',
				     'REFERENCE: a',
				     'match from 1 to 2 (length=1)',
				     'LITERAL: "a"',
				     'match from 1 to 2 (length=1)',
				     'REFERENCE: ~',
				     'match from 2 to 3 (length=1)',
				     'REFERENCE: b',
				     'match from 3 to 4 (length=1)',
				     'LITERAL: "b"',
				     'match from 3 to 4 (length=1)',
				     'REFERENCE: ~',
				     'fail at 4'})
----------------------------------------------------------------------------------------
heading("Eval raw groups")
----------------------------------------------------------------------------------------
check_eval('{a b}', "a b ", false, {'SEQUENCE: (a b)',
				    'fail at 1',
				    'REFERENCE: a',
				    'match from 1 to 2 (length=1)',
				    'LITERAL: "a"',
				    'match from 1 to 2 (length=1)',
				    'REFERENCE: b',
				    'fail at 2',
				    'LITERAL: "b"',
				    'fail at 2'})


check_eval('{a b}', "abx", true, {'SEQUENCE: (a b)',
				  'match from 1 to 3 (length=2)',
				  'REFERENCE: a',
				  'match from 1 to 2 (length=1)',
				  'LITERAL: "a"',
				  'match from 1 to 2 (length=1)',
				  'REFERENCE: b',
				  'match from 2 to 3 (length=1)',
				  'LITERAL: "b"',
				  'match from 2 to 3 (length=1)'})

check_eval('({a b})~', "abx", false, {'SEQUENCE: (a b ~ ~)',
				      'fail at 1',
				      'SEQUENCE: (a b ~)',
				      'fail at 1',
				      'SEQUENCE: (a b)',
				      'match from 1 to 3 (length=2)',
				      'REFERENCE: a',
				      'match from 1 to 2 (length=1)',
				      'LITERAL: "a"',
				      'match from 1 to 2 (length=1)',
				      'REFERENCE: b',
				      'match from 2 to 3 (length=1)',
				      'LITERAL: "b"',
				      'match from 2 to 3 (length=1)',
				      'REFERENCE: ~',
				      'fail at 3'})

----------------------------------------------------------------------------------------
heading("Eval look-ahead")
----------------------------------------------------------------------------------------
check_eval('a @b', "a b", true, {'SEQUENCE: (a ~ @b)',
				 'match from 1 to 3 (length=2)',
				 'SEQUENCE: (a ~)',
				 'match from 1 to 3 (length=2)',
				 'REFERENCE: a',
				 'match from 1 to 2 (length=1)',
				 'LITERAL: "a"',
				 'match from 1 to 2 (length=1)',
				 'REFERENCE: ~',
				 'match from 2 to 3 (length=1)',
				 'PREDICATE: @b',
				 'match from 3 to 3 (length=0)',
				 'REFERENCE: b',
				 'match from 3 to 4 (length=1)',
				 'LITERAL: "b"',
				 'match from 3 to 4 (length=1)'})

check_eval('{a @b}', "ab", true, {'SEQUENCE: (a @b)',
				  'match from 1 to 2 (length=1)',
				  'REFERENCE: a',
				  'match from 1 to 2 (length=1)',
				  'LITERAL: "a"',
				  'match from 1 to 2 (length=1)',
				  'PREDICATE: @b',
				  'match from 2 to 2 (length=0)',
				  'REFERENCE: b',
				  'match from 2 to 3 (length=1)',
				  'LITERAL: "b"',
				  'match from 2 to 3 (length=1)'})

check_eval('{a @b}', "a", false, {'SEQUENCE: (a @b)',
				  'fail at 1',
				  'REFERENCE: a',
				  'match from 1 to 2 (length=1)',
				  'LITERAL: "a"',
				  'match from 1 to 2 (length=1)',
				  'PREDICATE: @b',
				  'fail at 2',
				  'REFERENCE: b',
				  'fail at 2',
				  'LITERAL: "b"',
				  'fail at 2'})

----------------------------------------------------------------------------------------
heading("Eval negative look-ahead")
----------------------------------------------------------------------------------------
check_eval('a !b', "ax", false, {'SEQUENCE: (a ~ !b)',
				 'fail at 1',
				 'SEQUENCE: (a ~)',
				 'fail at 1',
				 'REFERENCE: a',
				 'match from 1 to 2 (length=1)',
				 'LITERAL: "a"',
				 'match from 1 to 2 (length=1)',
				 'REFERENCE: ~',
				 'fail at 2'})

check_eval('{a !b}', "ax", true, {'SEQUENCE: (a !b)',
				  'match from 1 to 2 (length=1)',
				  'REFERENCE: a',
				  'match from 1 to 2 (length=1)',
				  'LITERAL: "a"',
				  'match from 1 to 2 (length=1)',
				  'PREDICATE: !b',
				  'match from 2 to 2 (length=0)',
				  'REFERENCE: b',
				  'fail at 2',
				  'LITERAL: "b"',
				  'fail at 2'})

----------------------------------------------------------------------------------------
heading("Eval precedence and right association")
----------------------------------------------------------------------------------------
check_eval('a b / c', 'b c', false, {'SEQUENCE: (a ~ b / c)',
				     'fail at 1',
				     'SEQUENCE: (a ~)',
				     'fail at 1',
				     'REFERENCE: a',
				     'fail at 1',
				     'LITERAL: "a"',
				     'fail at 1'})

check_eval('a b / c', 'a c', true, {'SEQUENCE: (a ~ b / c)',
				    'match from 1 to 4 (length=3)',
				    'SEQUENCE: (a ~)',
				    'match from 1 to 3 (length=2)',
				    'REFERENCE: a',
				    'match from 1 to 2 (length=1)',
				    'LITERAL: "a"',
				    'match from 1 to 2 (length=1)',
				    'REFERENCE: ~',
				    'match from 2 to 3 (length=1)',
				    'CHOICE: b / c',
				    'match from 3 to 4 (length=1)',
				    'REFERENCE: b',
				    'fail at 3',
				    'LITERAL: "b"',
				    'fail at 3',
				    'REFERENCE: c',
				    'match from 3 to 4 (length=1)',
				    'LITERAL: "c"',
				    'match from 3 to 4 (length=1)'})

check_eval('a b / c {3,3}', 'a ccc', true, {'SEQUENCE: (a ~ b / {c}{3,3})',
					    'match from 1 to 6 (length=5)',
					    'SEQUENCE: (a ~)',
					    'match from 1 to 3 (length=2)',
					    'REFERENCE: a',
					    'match from 1 to 2 (length=1)',
					    'LITERAL: "a"',
					    'match from 1 to 2 (length=1)',
					    'REFERENCE: ~',
					    'match from 2 to 3 (length=1)',
					    'CHOICE: b / {c}{3,3}',
					    'match from 3 to 6 (length=3)',
					    'REFERENCE: b',
					    'fail at 3',
					    'LITERAL: "b"',
					    'fail at 3',
					    'QUANTIFIED EXP: (raw): {c}{3,3}',
					    'match from 3 to 6 (length=3)',
					    'The base expression must repeat at least 3 and at most 3 times, with no boundary between each repetition',
					    'BASE EXP: {c}',
					    'match from 3 to 4 (length=1)',
					    'BASE EXP: {c}',
					    'match from 4 to 5 (length=1)',
					    'BASE EXP: {c}',
					    'match from 5 to 6 (length=1)'})


check_eval('a b / c {3,3}', 'a cc', false, {'SEQUENCE: (a ~ b / {c}{3,3})',
					    'fail at 1',
					    'SEQUENCE: (a ~)',
					    'match from 1 to 3 (length=2)',
					    'REFERENCE: a',
					    'match from 1 to 2 (length=1)',
					    'LITERAL: "a"',
					    'match from 1 to 2 (length=1)',
					    'REFERENCE: ~',
					    'match from 2 to 3 (length=1)',
					    'CHOICE: b / {c}{3,3}',
					    'fail at 3',
					    'REFERENCE: b',
					    'fail at 3',
					    'LITERAL: "b"',
					    'fail at 3',
					    'QUANTIFIED EXP: (raw): {c}{3,3}',
					    'fail at 3',
					    'The base expression must repeat at least 3 and at most 3 times, with no boundary between each repetition',
					    'BASE EXP: {c}',
					    'match from 3 to 4 (length=1)',
					    'BASE EXP: {c}',
					    'match from 4 to 5 (length=1)',
					    'BASE EXP: {c}',
					    'fail at 5'})

print("\t ** Need more precedence and right association tests! **")

----------------------------------------------------------------------------------------
heading("Eval quantified expressions")
----------------------------------------------------------------------------------------
check_eval('a*', "", true, {'QUANTIFIED EXP: (raw): {a}*',
			    'match from 1 to 1 (length=0)',
			    'The base expression must repeat at least 0 and at most unlimited times, with no boundary between each repetition',
			    'BASE EXP: {a}',
			    'fail at 1'})

check_eval('a*', "aaaa", true, {'QUANTIFIED EXP: (raw): {a}*',
				'match from 1 to 5 (length=4)',
				'The base expression must repeat at least 0 and at most unlimited times, with no boundary between each repetition',
				'BASE EXP: {a}',
				'match from 1 to 2 (length=1)',
				'BASE EXP: {a}',
				'match from 2 to 3 (length=1)',
				'BASE EXP: {a}',
				'match from 3 to 4 (length=1)',
				'BASE EXP: {a}',
				'match from 4 to 5 (length=1)',
				'BASE EXP: {a}',
				'fail at 5'})

check_eval('a+', "", false, {'QUANTIFIED EXP: (raw): {a}+',
			     'fail at 1',
			     'The base expression must repeat at least 1 and at most unlimited times, with no boundary between each repetition',
			     'BASE EXP: {a}',
			     'fail at 1'})

check_eval('a+', "a", true, {'QUANTIFIED EXP: (raw): {a}+',
			     'match from 1 to 2 (length=1)',
			     'The base expression must repeat at least 1 and at most unlimited times, with no boundary between each repetition',
			     'BASE EXP: {a}',
			     'match from 1 to 2 (length=1)',
			     'BASE EXP: {a}',
			     'fail at 2'})

check_eval('{a/b}+', "baaa", true, {'QUANTIFIED EXP: (raw): {a / b}+',
				    'match from 1 to 5 (length=4)',
				    'The base expression must repeat at least 1 and at most unlimited times, with no boundary between each repetition',
				    'BASE EXP: {a / b}',
				    'match from 1 to 2 (length=1)',
				    'BASE EXP: {a / b}',
				    'match from 2 to 3 (length=1)',
				    'BASE EXP: {a / b}',
				    'match from 3 to 4 (length=1)',
				    'BASE EXP: {a / b}',
				    'match from 4 to 5 (length=1)',
				    'BASE EXP: {a / b}',
				    'fail at 5'})

check_eval('{a/b}{3,5}', "baaa", true, {'QUANTIFIED EXP: (raw): {a / b}{3,5}',
					'match from 1 to 5 (length=4)',
					'The base expression must repeat at least 3 and at most 5 times, with no boundary between each repetition',
					'BASE EXP: {a / b}',
					'match from 1 to 2 (length=1)',
					'BASE EXP: {a / b}',
					'match from 2 to 3 (length=1)',
					'BASE EXP: {a / b}',
					'match from 3 to 4 (length=1)',
					'BASE EXP: {a / b}',
					'match from 4 to 5 (length=1)',
					'BASE EXP: {a / b}',
					'fail at 5'})

check_eval('{a/b}{3,5}', "ba", false, {'QUANTIFIED EXP: (raw): {a / b}{3,5}',
				       'fail at 1',
				       'The base expression must repeat at least 3 and at most 5 times, with no boundary between each repetition',
				       'BASE EXP: {a / b}',
				       'match from 1 to 2 (length=1)',
				       'BASE EXP: {a / b}',
				       'match from 2 to 3 (length=1)',
				       'BASE EXP: {a / b}',
				       'fail at 3'})

check_eval('(a*)', "", true, {'QUANTIFIED EXP: (raw): {a}*',
			      'match from 1 to 1 (length=0)',
			      'The base expression must repeat at least 0 and at most unlimited times, with no boundary between each repetition',
			      'BASE EXP: {a}',
			      'fail at 1'})

check_eval('(a*)', "aaaa", true, {'QUANTIFIED EXP: (raw): {a}*',
				  'match from 1 to 5 (length=4)',
				  'The base expression must repeat at least 0 and at most unlimited times, with no boundary between each repetition',
				  'BASE EXP: {a}',
				  'match from 1 to 2 (length=1)',
				  'BASE EXP: {a}',
				  'match from 2 to 3 (length=1)',
				  'BASE EXP: {a}',
				  'match from 3 to 4 (length=1)',
				  'BASE EXP: {a}',
				  'match from 4 to 5 (length=1)',
				  'BASE EXP: {a}',
				  'fail at 5'})

check_eval('(a+)', "", false, {'QUANTIFIED EXP: (raw): {a}+',
			       'fail at 1',
			       'The base expression must repeat at least 1 and at most unlimited times, with no boundary between each repetition',
			       'BASE EXP: {a}',
			       'fail at 1'})

check_eval('(a+)', "a", true, {'QUANTIFIED EXP: (raw): {a}+',
			       'match from 1 to 2 (length=1)',
			       'The base expression must repeat at least 1 and at most unlimited times, with no boundary between each repetition',
			       'BASE EXP: {a}',
			       'match from 1 to 2 (length=1)',
			       'BASE EXP: {a}',
			       'fail at 2'})

check_eval('({a/b}+)', "baaa", true, {'QUANTIFIED EXP: (raw): {a / b}+',
				      'match from 1 to 5 (length=4)',
				      'The base expression must repeat at least 1 and at most unlimited times, with no boundary between each repetition',
				      'BASE EXP: {a / b}',
				      'match from 1 to 2 (length=1)',
				      'BASE EXP: {a / b}',
				      'match from 2 to 3 (length=1)',
				      'BASE EXP: {a / b}',
				      'match from 3 to 4 (length=1)',
				      'BASE EXP: {a / b}',
				      'match from 4 to 5 (length=1)',
				      'BASE EXP: {a / b}',
				      'fail at 5'})

check_eval('({a/b}{3,5})', "baaa", true, {'QUANTIFIED EXP: (raw): {a / b}{3,5}',
					  'match from 1 to 5 (length=4)',
					  'The base expression must repeat at least 3 and at most 5 times, with no boundary between each repetition',
					  'BASE EXP: {a / b}',
					  'match from 1 to 2 (length=1)',
					  'BASE EXP: {a / b}',
					  'match from 2 to 3 (length=1)',
					  'BASE EXP: {a / b}',
					  'match from 3 to 4 (length=1)',
					  'BASE EXP: {a / b}',
					  'match from 4 to 5 (length=1)',
					  'BASE EXP: {a / b}',
					  'fail at 5'})

check_eval('({a/b}{3,5})', "ba", false, {'QUANTIFIED EXP: (raw): {a / b}{3,5}',
					 'fail at 1',
					 'The base expression must repeat at least 3 and at most 5 times, with no boundary between each repetition',
					 'BASE EXP: {a / b}',
					 'match from 1 to 2 (length=1)',
					 'BASE EXP: {a / b}',
					 'match from 2 to 3 (length=1)',
					 'BASE EXP: {a / b}',
					 'fail at 3'})

return test.finish()
