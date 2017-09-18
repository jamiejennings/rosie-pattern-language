-- -*- Mode: Lua; -*-                                                                             
--
-- rpl-mod-test.lua    test rpl 1.1 modules
--
-- © Copyright IBM Corporation 2017.
-- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
-- AUTHOR: Jamie A. Jennings

assert(TEST_HOME, "TEST_HOME is not set")

list = import "list"
map = assert(list.map)
environment = import "environment"
common = import "common"

check = test.check
heading = test.heading
subheading = test.subheading

test.start(test.current_filename())

----------------------------------------------------------------------------------------
heading("Import")
----------------------------------------------------------------------------------------

e = rosie.engine.new()
e.searchpath = TEST_HOME

ok, _, msgs = e:load("import mod1")
check(ok)
m = e.env:lookup("mod1")
check(m)
check(m and environment.is(m))

p = e.env:lookup("S", "mod1")
check(p)
check(common.pattern.is(p))

p = e.env:lookup("A", "mod1")
check(not p)					    -- A is a local grammar

ok, m, left, t0, t1, msgs = e:match("mod1.S", "baab")
check(ok)
check(m)
check(left==0)
check(type(t0)=="number")
check(type(t1)=="number")
check(not msgs)
check(m.type=="mod1.S")
check(m.subs and m.subs[1] and m.subs[1].type=="mod1.S.A")
check(m.subs[1].subs and m.subs[1].subs[1] and m.subs[1].subs[1].type=="mod1.S")
check(m.subs[1].subs[1].subs and m.subs[1].subs[1].subs[1] and m.subs[1].subs[1].subs[1].type=="mod1.S.B")

-- compile error below, so instead of leftover chars, there is a table of messages
ok, m, left, t0, t1, msgs = e:match("mod1.foooooooo", "ababab")
check(not ok)
check(type(m)=="table")
check(#m==1)

ok, _, msgs = e:load("thisfiledoesnotexist!")
check(not ok)
check(type(msgs)=="table")

ok, _, msgs = e:load("import mod2")
check(ok)
p = e.env:lookup("x", "mod2")
check(not p)					    -- x is declared local
p = e.env:lookup("y", "mod2")
check(p)

ok, _, msgs = e:load("import mod2 as foobar")
check(ok)
p = e.env:lookup("x", "foobar")
check(not p)
p = e.env:lookup("y", "foobar")
check(p)

p = e.env:lookup("x")
check(not p)
p = e.env:lookup("y")
check(not p)

ok, pkgname, msgs = e:load("import mod2 as .")
check(ok)
check(not pkgname)
p = e.env:lookup("x")
check(not p)
p = e.env:lookup("y")
check(p)

ok, pkgname, msgs = e:load("import mod3")
check(ok)
check(not pkgname)
p = e.env:lookup("mod3")
check(not p)
p = e.env:lookup("y", "name_is_unexpectedly_different_from_file_name")
check(p)

ok, m, left, t0 = e:match("name_is_unexpectedly_different_from_file_name.y", "hello world")
check(ok)
check(m)
--table.print(m, false)

-- ensure that the package name is the one in the module source (i.e. the package declaration in
-- mod3.rpl) and not the name in the import declaration ("import mod3" above).
check(m.type=="name_is_unexpectedly_different_from_file_name.y")
check(left==0)
check(m.subs, "missing submatch for x")
check(m.subs and m.subs[1].type=="name_is_unexpectedly_different_from_file_name.x")

-- x is local to mod3.  make sure we cannot see it.
p = e.env:lookup("name_is_unexpectedly_different_from_file_name.x")
check(not p)

-- check that "import as..." works
ok, pkgname, msgs = e:load("import mod3 as foo")
check(ok)
check(not pkgname)
ok, m, left, t0 = e:match("foo.y", "hello world")
check(ok)
check(m)
-- ensure that the package name is the one in the "as ..." part of the import declaration.
check(m.type=="foo.y")
check(left==0)
check(m.subs, "missing submatch for x")
check(m.subs and m.subs[1].type=="foo.x")


-- check the same for grammars
p = e.env:lookup("name_is_unexpectedly_different_from_file_name.gx") -- local
check(not p)
p = e.env:lookup("foo.gx")				    -- local
check(not p)
p = e.env:lookup("gy")				    -- not imported at top level
check(not p)
p = e.env:lookup("gy", "foo")
check(p)
ok, m, left, t0 = e:match("foo.gy", "hello world")
check(ok)
check(m)
check(m.type=="foo.gy")
check(left==0)
check(m.subs, "missing submatch for gx")
check(m.subs and m.subs[1].type=="foo.gx")


ok, pkgname, msgs = e:load("import mod4")
check(not ok)
check(not pkgname)
check(type(msgs)=="table")

ok, pkgname, msgs = e:load("import mod5")
check(not ok)
check(not pkgname)
check(type(msgs)=="table")
msg = table.concat(map(violation.tostring, msgs), "\n")
check(msg:find("unbound identifier"))
check(msg:find("package mod5"))

ok, pkgname, msgs = e:load("import mod6")
check(not ok)
check(not pkgname)
check(type(msgs)=="table")
msg = table.concat(map(violation.tostring, msgs), "\n")
check(msg:find("unexpected declaration"))
check(msg:find("package mod6"))

ok, pkgname, msgs = e:load("import mod7")
check(not ok)
check(not pkgname)
check(type(msgs)=="table")
msg = table.concat(map(violation.tostring, msgs), "\n")
check(msg:find("unexpected declaration"))
check(msg:find("rpl"))

ok, pkgname, msgs = e:load("package foo")
check(ok)
check(pkgname=="foo")


subheading("Circular dependencies")

ok, pkgname, msgs = e:import("mod_circular")
check(not ok)
check(not pkgname)
msg = table.concat(map(violation.tostring, msgs), "\n")
check(msg:find("circular"))
check(msg:find("mod_circular"))

ok, pkgname, msgs = e:import("mod_circular_1")
check(not ok)
check(not pkgname)
msg = table.concat(map(violation.tostring, msgs), "\n")
check(msg:find("circular"))
check(msg:find("mod_circular_1"))
check(msg:find("mod_circular_2"))



-- return the test results in case this file is being called by another one which is collecting
-- up all the results:
return test.finish()
