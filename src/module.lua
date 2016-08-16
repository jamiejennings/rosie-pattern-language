---- -*- Mode: Lua; -*-                                                                           
----
---- module.lua     Rosie's module system
----
---- © Copyright IBM Corporation 2016.
---- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
---- AUTHOR: Jamie A. Jennings

local common = require "common"
local compile = require "compile"

-- Import declaration        | Local name of word
-- ------------------------- | ------------------------------
-- import "lib/common"       | common.word
-- import "lib/common" as cm | cm.word
-- import "lib/math" as .    | word

--local module = {}

import_pats = [==[
      -- Specification for the import statement
      alias id_char = { [[:alnum:]] / [[-_]] }	    -- !@# CHECK THIS
      package_name = { [[:alpha:]] id_char* }
      package_name_dot = "."

      alias dquote = { [[\"]] }			      -- from rpl-core
      alias esc =    { [[\\]] }			      -- from rpl-core
      literal = { {!{esc/dquote} .} / {esc .} }*      -- from rpl-core
      alias quoted_string = { dquote literal dquote } -- from rpl-core
      import_path = quoted_string 

      import_spec = import_path ("as" (package_name / package_name_dot))?
      import = "import" import_spec (";" import_spec)* 

      -- Specification for the package statement
      package = "package" package_name
   ]==]

e  = lapi.new_engine{name="import testing"}
lapi.load_string(e, import_pats)

assert(pattern.is(e.env.import))

require "test-functions"
check = test.check

assert(lapi.configure_engine(e, {expression="package", encode=false}))

m, leftover = lapi.match(e, 'package')
check(not m)
m, leftover = lapi.match(e, 'package foo')
check(m and (leftover==0))
m, leftover = lapi.match(e, 'package fooBar')
check(m and (leftover==0))
m, leftover = lapi.match(e, 'package f_oo')
check(m and (leftover==0))
m, leftover = lapi.match(e, 'package _foo')
check(not m)
m, leftover = lapi.match(e, 'package 6foo')
check(not m)
m, leftover = lapi.match(e, 'package .foo')
check(not m)
m, leftover = lapi.match(e, 'package foo.bar')
check(m and (leftover==4))


assert(lapi.configure_engine(e, {expression="import", encode=false}))

m, leftover = lapi.match(e, 'import ')
check(not m)
m, leftover = lapi.match(e, 'import "foo/bar"')
check(m and (leftover==0))
m, leftover = lapi.match(e, 'import "foo/bar";')
check(m and (leftover==1))
check(lapi.match(e, 'import "foo/bar"; "/usr/local/baz"; "/usr/bin/time"'))
check(lapi.match(e, 'import "foo/bar" as foo; "/usr/local/baz"; "/usr/bin/time"'))
m, leftover = lapi.match(e, 'import "foo/bar" as foo; "/usr/local/baz" as . ; "/usr/bin/time"')
check(m and (leftover==0))
check(m.import and m.import.subs and #m.import.subs==3)
tbl = {}; foreach(function(s)
		     tbl[s.import_spec.subs[1].import_path.subs[1].literal.text] =
			s.import_spec.subs[2] and
			((s.import_spec.subs[2].package_name
			  and s.import_spec.subs[2].package_name.text)
		      or (s.import_spec.subs[2].package_name_dot
			  and s.import_spec.subs[2].package_name_dot.text))
		     or ""; end, 
		  m.import.subs)
check(tbl["/usr/bin/time"])
check(tbl["/usr/local/baz"] == ".")
check(tbl["foo/bar"] == "foo")
print();
table.print(tbl)


