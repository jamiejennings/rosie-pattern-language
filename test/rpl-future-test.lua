-- -*- Mode: Lua; -*-                                                               
--
-- rpl-future-test.lua
--
-- © Copyright Jamie A. Jennings 2018.
-- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
-- AUTHOR: Jamie A. Jennings

assert(TEST_HOME, "TEST_HOME is not set")

list = import "list"
map = list.map
violation = import "violation"
common = import "common"

check = test.check
heading = test.heading
subheading = test.subheading

test.start(test.current_filename())

---------------------------------------------------------------------------------------------------
heading("Setting up")

check(type(rosie)=="table")
e = rosie.engine.new("rpl future test")
check(rosie.engine.is(e))


function check_syntax_error(errs)
   local msg = table.concat(map(violation.tostring, errs), "\n")
   check(msg:find("Syntax error"), "error was:\n" .. msg, 1)
end

function check_valid_grammar(ok, errs, bound_name)
   check(ok, "loading the rpl code failed?!", 1)
   check(#errs == 0, "errors where none were expected", 1)
   local value = e.env:lookup(bound_name)
   check(common.pattern.is(value), "did not bind " .. bound_name .. " as expected", 1)
end

function check_unsupported(rplx, errs, error_message_fragment)
   check(not rplx, "compiling succeeded?!", 1)
   check_syntax_error(errs)
   local msg = table.concat(map(violation.tostring, errs), '\n')
   check(msg:find(error_message_fragment),
	 "error message did not include expected phrase", 1)
end

---------------------------------------------------------------------------------------------------
heading("RPL 1.2 grammar syntax")

subheading("Statements")

ok, _, errs = e:load('grammar foobar="foo" end')
check_valid_grammar(ok, errs, 'foobar')

ok, _, errs = e:load('grammar foo="f00" in foobar2=foo foo end')
check_valid_grammar(ok, errs, 'foobar2')
check(not e.env:lookup('foo'))

ok, _, errs = e:load('grammar foo2="f22" in foo3="f00" foobar3=foo3 foo3 end')
check(not ok)
check(not e.env:lookup('foo3'))
check(not e.env:lookup('foobar3'))
msg = table.concat(map(violation.tostring, errs), '\n')
check(msg:find("one rule allowed in public section"))

ok, _, errs = e:load('grammar foo3="f00" foobar3=foo3 foo3 end')
check(not ok)
check(not e.env:lookup('foo3'))
check(not e.env:lookup('foobar3'))
msg = table.concat(map(violation.tostring, errs), '\n')
check(msg:find("one rule allowed in public section"))

ok, _, errs = e:load('grammar ; in foo3="f00" foobar3=foo3 foo3 end')
check(not ok)
check(not e.env:lookup('foo3'))
check(not e.env:lookup('foobar3'))
msg = table.concat(map(violation.tostring, errs), '\n')
check(msg:find("one rule allowed in public section"))

ok, _, errs = e:load('grammar ;;;;; in foo3="f00" foobar3=foo3 foo3 end')
check(not ok)
check(not e.env:lookup('foo3'))
check(not e.env:lookup('foobar3'))
msg = table.concat(map(violation.tostring, errs), '\n')
check(msg:find("one rule allowed in public section"))

ok, _, errs = e:load('grammar foo4="f44" ; end')
check_valid_grammar(ok, errs, 'foo4')

ok, _, errs = e:load('grammar foo5="f55" ;;; end')
check_valid_grammar(ok, errs, 'foo5')

ok, _, errs = e:load('grammar in foo6="f66" end')
check(not ok)
check_syntax_error(errs)

ok, _, errs = e:load('grammar foo6="f66" in end')
check(not ok)
check_syntax_error(errs)

ok, _, errs = e:load('grammar ; in foo6="f66" end')
check_valid_grammar(ok, errs, 'foo6')


subheading("Expressions")

rplx, errs = e:compile('grammar')
check(not rplx)
check_syntax_error(errs)
msg = table.concat(map(violation.tostring, errs), '\n')
check(msg:find("while reading expression"))

rplx, errs = e:compile('grammar in')
check(not rplx)
check_syntax_error(errs)
msg = table.concat(map(violation.tostring, errs), '\n')
check(msg:find("while reading expression"))

rplx, errs = e:compile('grammar ; in ;')
check(not rplx)
check_syntax_error(errs)
msg = table.concat(map(violation.tostring, errs), '\n')
check(msg:find("while reading expression"))

rplx, errs = e:compile('grammar ; in ; end')
check(not rplx)
check_syntax_error(errs)
msg = table.concat(map(violation.tostring, errs), '\n')
check(msg:find("found statement where expression was expected"))

ok, _, errs = e:load('grammar bar="bar" in bar end')
check(not ok)
check_syntax_error(errs)
msg = table.concat(map(violation.tostring, errs), '\n')
check(msg:find("while reading statement"))

rplx, errs = e:compile('grammar bar="bar" in bar end')
check(not rplx)
check_syntax_error(errs)
msg = table.concat(map(violation.tostring, errs), '\n')
check(msg:find("while reading expression"))

rplx, errs = e:compile('grammar X bar="bar" in X end')
check(not rplx)
check_syntax_error(errs)
msg = table.concat(map(violation.tostring, errs), '\n')
check(msg:find("extraneous input: end"))

rplx, errs = e:compile('grammar X bar="bar" in X')
check_unsupported(rplx, errs, "grammar expressions are not supported")

rplx, errs = e:compile('grammar X bar="bar" in bar')
check_unsupported(rplx, errs, "grammar expressions are not supported")

rplx, errs = e:compile('grammar X bar="bar" foo="foo" in foo bar')
check_unsupported(rplx, errs, "grammar expressions are not supported")


---------------------------------------------------------------------------------------------------
heading("RPL 1.2 let syntax")
	
subheading("Statements")

ok, _, errs = e:load('let bar="bar" in baz=bar+ end')
check(not ok)
check_unsupported(ok, errs, "let statements are not supported")

rplx, errs = e:compile('let bar="bar" in baz=bar+ end')
check(not rplx)
check_syntax_error(errs)
msg = table.concat(map(violation.tostring, errs), '\n')
check(msg:find("found statement where expression was expected"))

ok, _, errs = e:load('let bar="bar" in bar')
check(not ok)
check_syntax_error(errs)
msg = table.concat(map(violation.tostring, errs), '\n')
check(msg:find("found expression where statement was expected"))

ok, _, errs = e:load('let ; in bar end')
check(not ok)
check_syntax_error(errs)
msg = table.concat(map(violation.tostring, errs), '\n')
check(msg:find("while reading statement"))

ok, _, errs = e:load('let ;;;;;; in bar end')
check(not ok)
check_syntax_error(errs)
msg = table.concat(map(violation.tostring, errs), '\n')
check(msg:find("while reading statement"))

ok, _, errs = e:load('let in bar end')
check(not ok)
check_syntax_error(errs)
msg = table.concat(map(violation.tostring, errs), '\n')
check(msg:find("while reading statement"))

ok, _, errs = e:load('let foo="foo" in')
check(not ok)
check_syntax_error(errs)
msg = table.concat(map(violation.tostring, errs), '\n')
check(msg:find("while reading statement"))

ok, _, errs = e:load('let foo= in')
check(not ok)
check_syntax_error(errs)

ok, _, errs = e:load('let foo')
check(not rplx)
check_syntax_error(errs)
msg = table.concat(map(violation.tostring, errs), '\n')
check(msg:find("found expression where statement was expected"))

ok, _, errs = e:load('let end')
check(not rplx)
check_syntax_error(errs)
msg = table.concat(map(violation.tostring, errs), '\n')
check(msg:find("syntax error while reading statement"))

ok, _, errs = e:load('let bar="bar" foo="foo" in foo=bar end')
check_unsupported(rplx, errs, "let statements are not supported")


subheading("Expressions")

ok, _, errs = e:load('let bar="bar" in bar end')
check(not ok)
check_syntax_error(errs)
msg = table.concat(map(violation.tostring, errs), '\n')
check(msg:find("while reading statement"))

rplx, errs = e:compile('let bar="bar" in bar end')
check(not rplx)
check_syntax_error(errs)
msg = table.concat(map(violation.tostring, errs), '\n')
check(msg:find("extraneous input: end"))

rplx, errs = e:compile('let bar="bar" in bar')
check_unsupported(rplx, errs, "let expressions are not supported")

rplx, errs = e:compile('let ; in bar')
check_unsupported(rplx, errs, "let expressions are not supported")

rplx, errs = e:compile('let ;;;;;; in bar')
check_unsupported(rplx, errs, "let expressions are not supported")
msg = table.concat(map(violation.tostring, errs), '\n')

rplx, errs = e:compile('let in bar')
check(not rplx)
check_syntax_error(errs)
msg = table.concat(map(violation.tostring, errs), '\n')
check(msg:find("while reading expression"))

rplx, errs = e:compile('let foo="foo" in')
check(not rplx)
check_syntax_error(errs)
msg = table.concat(map(violation.tostring, errs), '\n')
check(msg:find("while reading expression"))

rplx, errs = e:compile('let foo= in')
check(not rplx)
check_syntax_error(errs)
msg = table.concat(map(violation.tostring, errs), '\n')
check(msg:find("extraneous input: = in"))

rplx, errs = e:compile('let foo')
check(not rplx)
check_syntax_error(errs)
check_unsupported(rplx, errs, "let expressions are not supported")

rplx, errs = e:compile('let')
check(not rplx)
check_syntax_error(errs)
msg = table.concat(map(violation.tostring, errs), '\n')
check(msg:find("while reading expression"))

rplx, errs = e:compile('let bar="bar" foo="foo" in foo bar')
check_unsupported(rplx, errs, "let expressions are not supported")


-- return the test results in case this file is being called by another one which is collecting
-- up all the results:
return test.finish()

