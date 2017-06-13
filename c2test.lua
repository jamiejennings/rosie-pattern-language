rosie = require "rosie"
e = rosie.engine.new()

list = rosie._env.list
util = rosie._env.util
common = rosie._env.common
environment = rosie._env.environment
ast = rosie._env.ast
loadpkg = rosie._env.loadpkg
c2 = rosie._env.c2
decode = rosie._env.lpeg.decode


-- global tables of intermediate results for examination during testing:
parses = {}
asts = {}

e:load("import rosie/rpl_1_1 as .")
RPLX_PREPARSE = e:compile("preparse")
RPLX_STATEMENTS = e:compile("rpl_statements")
RPLX_EXPRESSION = e:compile("rpl_expression")

version = common.rpl_version.new(1, 1)

c = {parse_block = c2.make_parse_block(RPLX_PREPARSE, RPLX_STATEMENTS, version),
     parse_expression = c2.make_parse_expression(RPLX_EXPRESSION),
     expand_block = c2.expand_block,
     compile_block = c2.compile_block}

messages = {}
pkgtable = environment.make_module_table()
env = environment.new()

function printf(fmt, ...)
   print(string.format(fmt, ...))
end

function dump_state()
   print("\nPkgtable:")
   print("---------")
   for k,v in pairs(pkgtable) do printf("%-10s %s", k, tostring(v)); end
   print("\nTop level env:")
   print("--------------")
   for k,v in env:bindings() do printf("%-15s %s", k, tostring(v)); end
   print()
end

function goimport(importpath)
   print("Loading " .. importpath)
   fullpath, src, errmsg = common.get_file(importpath, e.searchpath)
   if (not src) then error("go: failed to find import " .. importpath); end
   loadpkg.source(c, pkgtable, env, e.searchpath, src, importpath, fullpath, messages)
   dump_state()
end

function go(src)
   print("Loading source: " .. src:sub(1,60))
   loadpkg.source(c, pkgtable, env, e.searchpath, src, nil, nil, messages)
   dump_state()
end   


goimport("num")
goimport("net")

go("import common")
go("import common as foo")
go("import net, common as .")


print("\n----- Start of cooked/raw tests -----\n")


function test_seq(name, expectation)
   local foo = environment.lookup(env, name)
   assert(ast.binding.is(foo.ast))
   seq = list.map(function(ex)
		     if ast.ref.is(ex) then return ex.localname
		     elseif ast.predicate.is(ex) then return "predicate"
		     else return tostring(ex)
		     end
		  end,
		  foo.ast.exp.exps)
   print(name, seq)
   if list.equal(seq, list.from(expectation)) then
      print("Correct")
   else
      error("WRONG RESULT!")
   end
end

go('foo = a b c')
test_seq("foo", {"a", "~", "b", "~", "c"})

go('foo = {a b c}')
test_seq("foo", {"a", "b", "c"})

go('foo = ({a b c})')
test_seq("foo", {"a", "b", "c"})

go('foo = {({a b c})}')
test_seq("foo", {"a", "b", "c"})

go('foo = {(a b c)}')
test_seq("foo", {"a", "~", "b", "~", "c"})

go('foo = (!a b c)')
test_seq("foo", {"predicate", "b", "~", "c"})

go('foo = (!a b @c)')
test_seq("foo", {"predicate", "b", "~", "predicate"})

go('foo = (!a @b c)')
test_seq("foo", {"predicate", "predicate", "c"})

go('foo = (!a @b !c)')
test_seq("foo", {"predicate", "predicate", "predicate"})

go('foo = !a @b !c')
test_seq("foo", {"predicate", "predicate", "predicate"})

go('foo = {!a @b !c}')
test_seq("foo", {"predicate", "predicate", "predicate"})

go('foo = a / b / c')
test_seq("foo", {"a", "b", "c"})

go('foo = {a / b / c}')
test_seq("foo", {"a", "b", "c"})

go('foo = (a / b / c)')
test_seq("foo", {"a", "b", "c"})

goimport("json"); print(ast.tostring(c2.asts.json), "\n")
goimport("date"); print(ast.tostring(c2.asts.date), "\n")
goimport("time"); print(ast.tostring(c2.asts.time), "\n")
goimport("os"); print(ast.tostring(c2.asts.os), "\n")

print("--- Testing compile_expression ---")

n = c2.compile_expression(c2.expand_expression(c.parse_expression("net.any", messages)), env, messages)
assert(n)
table.print(decode(n.peg:rmatch("1.2.3.4")))
print("match against 1.2.3.4 OK")

m, leftover = n.peg:rmatch("aksdlaksdlsakd")
assert(not m)
assert(leftover==14)
print("non-match against aksdlaksdlsakd OK")


go('foo = net.any')
n2 = c2.compile_expression(c2.expand_expression(c.parse_expression("foo", messages)), env, messages)
assert(n2)
table.print(decode(n2.peg:rmatch("1.2.3.4")))
print("match against 1.2.3.4 OK")


go('alias afoo = net.any')
n3 = c2.compile_expression(c2.expand_expression(c.parse_expression("afoo", messages)), env, messages)
assert(n3)
table.print(decode(n3.peg:rmatch("1.2.3.4")))
print("match against 1.2.3.4 OK")

n4 = c2.compile_expression(c2.expand_expression(c.parse_expression("common.word afoo", messages)), env, messages)
assert(n4)
table.print(decode(n4.peg:rmatch("hello 1.2.3.4")))
print("match against hello 1.2.3.4 OK")




