---- -*- Mode: Lua; -*- 
----
---- test.lua    These little tests need to grow into a full test suite
----
---- (c) 2015, Jamie A. Jennings
----

require "dev"
local compile = require "compile"

local n = #do_manifest(ENGINE, ROSIE_HOME.."/MANIFEST")
print(n .. " patterns loaded into matching engine named '" .. ENGINE.name .. "'")

function test()
   test_compiling_stuff()
   compiler_sniff_test()
   test_expressions()
end

----------------------------------------------------------------------------------------
-- Testing different kinds of things
----------------------------------------------------------------------------------------

function test_compiling_stuff()
   process_manifest(ENGINE, ROSIE_HOME .. "/MANIFEST")
   print();
   print("Environment in default engine:")
   compile.print_env(ENGINE.env)
   local count=0
   for k,v in pairs(ENGINE.env) do count = count+1; end
   print(count .. " patterns defined in environment (including aliases)")
   print()
end

function compiler_sniff_test()
   print("Running compiler sniff test...")
   if not ENGINE.env.digit then error("'digit' not defined in default engine. Was test_compiler() run?"); end
   compile.compile('foo = digit+ / letter', ENGINE.env)
   t = match("foo", "!xyz");
   assert(not t)
   t = match("foo", "1xyz");
   assert(not t)
   t = match("foo", "1 xyz"); table.print(t)
   assert(type(t)=="table" and t.foo and t.foo.text=="1")
   t = match("foo", "12345\t\nxyz"); table.print(t)
   assert(type(t)=="table" and t.foo and t.foo.text=="12345")
   t = match("foo", "x"); table.print(t)
   assert(type(t)=="table" and t.foo and t.foo.text=="x")
   t = match("foo", "x yz"); table.print(t)
   assert(type(t)=="table" and t.foo and t.foo.text=="x")
   t = match("foo", "xyz");
   assert(not t)
end

-- Precedence/associativity examples
-- 
--    a / b c      ==  a / (b c)   
--    a b / c d    ==  a (b / (c d))
--    ! a b c      ==  (!a) b c
--    a b c *      ==  a b (c*)
--    ! a *        ==  !(a*)

function test_expressions()
   ex = 'a="a" b="b" c="c" d="d"'
   compile.compile(ex, ENGINE.env)

   print("Testing a / b c, which is equivalent to a / (b c)")
   compile.compile('test = a / b c', ENGINE.env)
   result = match("test", 'a')
   -- [test: [1: a, 2: [a: [1: a]]]]
   assert(result and result.test and result.test.text=="a")
   result = match("test", 'ac')
   assert(not result)
   result = match("test", 'a c')
   assert(result and result.test and result.test.text=="a")
   -- Warning: did not match entire input line
   -- [test: [1: a, 2: [a: [1: a]]]]
   assert(result and result.test and result.test.text=="a")
   result = match("test", 'bc')
   assert (not result)
   result = match("test", 'b c')
   -- [test: [1: b c, 2: [b: [1: b]], 3: [c: [1: c]]]]
   assert(result and result.test and result.test.text=="b c")
   result = match("test", 'a c')
   -- Warning: did not match entire input line
   -- [test: [1: a, 2: [a: [1: a]]]]
   assert(result and result.test and result.test.text=="a")

   print("Testing a b / c d, which is equivalent to a (b / (c d))")
   compile.compile('test = a b / c d', ENGINE.env)
   result = match("test", 'a b')
   -- [test: [1: a b, 2: [a: [1: a]], 3: [b: [1: b]]]]
   assert(result and result.test and result.test.text=="a b")
   result = match("test", 'a b d')
   -- Warning: did not match entire input line
   -- [test: [1: a b, 2: [a: [1: a]], 3: [b: [1: b]]]]
   assert(result and result.test and result.test.text=="a b")
   result = match("test", 'a c d')
   -- [test: [1: a c d, 2: [a: [1: a]], 3: [c: [1: c]], 4: [d: [1: d]]]]
   assert(result and result.test and result.test.text=="a c d")

   print("Testing ! a b c, which is equivalent to !a (b c)")
   compile.compile('test = ! a b c', ENGINE.env)
   result = match("test", 'a b c')
   -- Error: deep_table_concat_pairs called with nil table
   assert(not result)
   result = match("test", 'x')
   -- Error: deep_table_concat_pairs called with nil table
   assert(not result)
   result = match("test", 'x b c')
   -- Error: deep_table_concat_pairs called with nil table
   assert(not result)
--   print("    The test against input 'b c' reveals a bug that we need to fix about leading spaces")
   result = match("test", 'b c')
   -- [test: [1: b c, 2: [b: [1: b]], 3: [c: [1: c]]]]
   assert(result and result.test and result.test.text=="b c")
--   print("    The test against input ' b c' highlists treatment of leading whitespace")
--   result = match("test", ' b c')
--   -- [test: [1: b c, 2: [b: [1: b]], 3: [c: [1: c]]]]
--   assert(result and result.test and result.test.text=="b c")

   print("Testing a b c*, which is equivalent to a b (c*)")
   compile.compile('test = a b c *', ENGINE.env)
   result = match("test", 'a b c')
   -- [test: [1: a b c, 2: [a: [1: a]], 3: [b: [1: b]], 4: [c: [1: c]]]]
   assert(result and result.test and result.test.text=="a b c")
   result = match("test", 'a b c a b c')
   -- Warning: did not match entire input line
   -- [test: [1: a b c, 2: [a: [1: a]], 3: [b: [1: b]], 4: [c: [1: c]]]]
   assert(result and result.test and result.test.text=="a b c")
   result = match("test", 'a b c c c')
   -- Warning: did not match entire input line
   -- [test: [1: a b c, 2: [a: [1: a]], 3: [b: [1: b]], 4: [c: [1: c]]]]
   assert(result and result.test and result.test.text=="a b c")
   result = match("test", 'a b ccc')
   -- [test: [1: a b ccc, 2: [a: [1: a]], 3: [b: [1: b]], 4: [c: [1: c]], 5: [c: [1: c]], 6: [c: [1: c]]]]
   assert(result and result.test and result.test.text=="a b ccc")

   print("Testing a b (c)*, for contrast with a b c*, noting that c* is raw whereas (c)* is cooked")
   compile.compile('test = a b (c)*', ENGINE.env)
   result = match("test", 'a b ccc')
   -- Warning: did not match entire input line
   -- [test: [1: a b , 2: [a: [1: a]], 3: [b: [1: b]]]]
   assert(result and result.test and result.test.text=="a b ")
   result = match("test", 'a b c c c')
   -- [test: [1: a b c c c, 2: [a: [1: a]], 3: [b: [1: b]], 4: [c: [1: c]], 5: [c: [1: c]], 6: [c: [1: c]]]]
   assert(result and result.test and result.test.text=="a b c c c")

   print("Testing !a+, which is equivalent to !(a+)")
   compile.compile('test = !a+', ENGINE.env)
   result = match("test", ' b')
   -- Warning: did not match entire input line
   -- [test: [1: ]]
   assert(result and result.test and result.test.text=="")
   result = match("test", 'b')
   -- Warning: did not match entire input line
   -- [test: [1: ]]
   assert(result and result.test and result.test.text=="")
   result = match("test", '')
   -- [test: [1: ]]
   assert(result and result.test and result.test.text=="")
   result = match("test", 'a')
   -- Error: deep_table_concat_pairs called with nil table
   assert(not result)
   result = match("test", 'aaa')
   -- Error: deep_table_concat_pairs called with nil table
   assert(not result)

   print("Testing a{1,2} against a, aa, aaa, and x")
   result = match('a{1,2}', 'a')
   assert(result and result['*'] and result['*'].text=="a")
   result = match('a{1,2}', 'aa')
   assert(result and result['*'] and result['*'].text=="aa")
   result = match('a{1,2}', 'aaa')
   assert(not result)
   result = match('a{1,2}', 'x')
   assert(not result)

   print("Testing a{0,1} against a, aa, and x")
   result = match('a{0,1}', 'a')
   assert(result and result['*'] and result['*'].subs[1].a.text=="a")
   result = match('a{0,1}', 'aa')
   assert(not result)
   result = match('a{0,1}', 'x')
   assert(result and result['*'] and result['*'].text=="")

   print("Confirming that a{0,1} is not equivalent to a?")
   result = match('a{0,1}', 'aa')
   assert(not result)
   result = match('a?', 'aa')
   assert(result and result['*'] and result['*'].text=="a")

   print("Testing a simple grammar")
   -- match strings that have the same number of a's as b's.  match 'same $' to check an entire
   -- string. 
   local g = [[
	grammar
	  same = S $
	  S = {"a" B} / {"b" A} / "" 
	  A = {"a" S} / {"b" A A}
	  B = {"b" S} / {"a" B B}
	end
  ]]

  -- grammars are statements, not expressions, at least at this point in time.  so we must compile
  -- the grammar first, then refer to it by its assigned name.
  compile.compile(g, ENGINE.env)
  result = match('same', 'aababb')
  assert(result and result['same'] and result['same'].text=="aababb")
  result = match('same', 'aababbb')
  assert(not result)

  print("Done.")
end

function test_eval()
   print("Testing EVAL...")
   ex = 'a="a" b="b" c="c" d="d"'
   compile.compile(ex, ENGINE.env)

   eval = function(source, input)
	     return eval.eval(source, input, 1, ENGINE.env)
	  end
   print('Eval literal string')
   assert(pcall(eval, '"a"', 'abc 123'))
   print('Eval character set (list)')
   assert(pcall(eval, '[bca]', 'abc 123'))
   print('Eval character set (range)')
   assert(pcall(eval, '[a-z]', 'abc 123'))
   print('Eval character set (named)')
   assert(pcall(eval, '[:alpha:]', 'abc 123'))
   print('Eval identifier')
   assert(pcall(eval, 'a', 'abc 123'))
   print('Eval sequence')
   assert(pcall(eval, 'a b', 'a b'))
   print('Eval raw group')
   assert(pcall(eval, '{a b}', 'ab'))
   print('Eval cooked group')
   assert(pcall(eval, '(a b)', 'a b'))
   print('Eval negation')
   assert(pcall(eval, '!"x" a b', 'a b'))
   print('Eval lookat')
   assert(pcall(eval, '@"x" a b', 'a b'))
   print('Eval quantifier *')
   assert(pcall(eval, 'a*', 'aaa b'))
   print('Eval quantifier +')
   assert(pcall(eval, 'a+', 'aaa b'))
   print('Eval quantifier ?')
   assert(pcall(eval, 'a? b', 'aaa b'))
   print('Eval quantifier range')
   assert(pcall(eval, 'a{3,3} b', 'aaa b'))
   print("Done.")
end
