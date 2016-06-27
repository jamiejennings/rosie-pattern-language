---- -*- Mode: Lua; -*- 
----
---- eval-test.lua
----
---- (c) 2016, Jamie A. Jennings
----

test = require "test-functions"
json = require "cjson"

check = test.check
heading = test.heading
subheading = test.subheading

function set_expression(exp)
   local ok, msg = api.configure_engine(eid, json.encode{expression=exp, encode="json"})
   if not ok then error("Configuration error: " .. msg); end
end

function check_match(...) error("Called check_match accidentally"); end

trace = "no trace set"

function check_eval(exp, input, expectation, expected_contents_list)
   set_expression(exp)
   local ok, results_js = api.eval(eid, input)
   check(ok, "failed call to api.eval: " .. tostring(results_js))
   if ok then
      local results = json.decode(results_js)
      local m, leftover, localtrace = table.unpack(results)
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
api = require "api"

check(type(api)=="table")
check(api.info)
check(type(api.info=="function"))

check(type(api.new_engine)=="function")
ok, eid_js = api.new_engine(json.encode{name="eval test"})
check(ok)
eid = json.decode(eid_js)[1]
check(type(eid)=="string")

subheading("Setting up assignments")
ok, msg = api.load_string(eid, 'a = "a"  b = "b"  c = "c"  d = "d"')
check(ok)
ok, msg = api.get_environment(eid, json.encode("a"))
check(ok)

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

----------------------------------------------------------------------------------------
heading("Eval built-ins")
----------------------------------------------------------------------------------------
print("\tNeed tests for built-ins like ., $, and ~")

----------------------------------------------------------------------------------------
heading("Eval literals")
----------------------------------------------------------------------------------------
check_eval('"foo"', "foo", true, {'1..LITERAL: "foo"', 'Matched "foo"'})
check_eval('"foo"', "foobar", true, {'1..LITERAL: "foo"', 'Matched "foo"'})
check_eval('"foo"', "notfoo", false, {'1..LITERAL: "foo"', 'FAILED to match'})

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

return test.finish()
