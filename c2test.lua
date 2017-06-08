rosie = require "rosie"
e = rosie.engine.new()

list = rosie._env.list
util = rosie._env.util
common = rosie._env.common
environment = rosie._env.environment
ast = rosie._env.ast
loadpkg = rosie._env.loadpkg
expand = rosie._env.expand

e:load("import rosie/rpl_1_1 as .")
c = {}
c.parse_block = function(src)
		   --print("load: entering parse_block")
		   local maj, min, start = e.compiler.parser.preparse(src)
		   if not maj then error("preparse failed"); end
		   local ok, pt, leftover = e:match("rpl_statements", src, start)
		   -- TODO: syntax error check
		   return pt, {}, leftover	    -- no warnings for now
		 end

c.expand_block = expand.block

c.compile_block = function(a, pkgtable, pkgenv, messages)
		     print("load: entering dummy compile_block, making novalue bindings")
		     for _, b in ipairs(a.stmts) do
			assert(ast.binding.is(b))
			local ref = b.ref
			local prefix = (ref.packagename and (ref.packagename .. ".") or "")
			if environment.lookup(pkgenv, ref.localname) then
			   print("      rebinding " .. prefix .. ref.localname)
			else
			   print("      creating novalue binding for " .. prefix .. ref.localname)
			end
			environment.bind(pkgenv,
					 ref.localname,
					 common.novalue.new{exported=true, ast=b})
		     end -- for
		     return true
		  end


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
   for k,v in env:bindings() do printf("%-10s %s", k, tostring(v)); end
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
   assert(common.novalue.is(foo))
   assert(ast.binding.is(foo.ast))
   assert(ast.sequence.is(foo.ast.exp) or ast.choice.is(foo.ast.exp))
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

