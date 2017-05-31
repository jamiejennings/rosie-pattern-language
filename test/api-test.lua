-- -*- Mode: Lua; -*-                                                                             
--
-- api-test.lua
--
-- © Copyright IBM Corporation 2016, 2017.
-- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
-- AUTHOR: Jamie A. Jennings

-- These tests are designed to run in the Rosie development environment, which is entered with: bin/rosie -D
assert(ROSIE_HOME, "ROSIE_HOME is not set?")
assert(type(rosie)=="table", "rosie package not loaded as 'rosie'?")
import = rosie._env.import
if not test then
   test = import("test")
end

lpeg = rosie._env.lpeg
json = rosie._env.cjson
environment = rosie._env.environment
lookup = environment.lookup

check = test.check
heading = test.heading
subheading = test.subheading

function invalid_id(msg)
   return msg:find("invalid engine id")
end

test.start(test.current_filename())

----------------------------------------------------------------------------------------
heading("Load the api")
----------------------------------------------------------------------------------------
api = import("api")
check(type(api)=="table")

---------------------------------------------------------------------------------------------------
-- Convenience

function wrap(f)
   return function (...)
	     local tbl = f(...)
	     return table.unpack(tbl)
	  end
end

wapi = {}
for k,v in pairs(api) do
   if type(v)=="function" then
      wapi[k] = wrap(v)
   end
end

---------------------------------------------------------------------------------------------------

subheading("info")
check(type(wapi.info)=="function")
ok, env_js = wapi.info()
check(ok)
check(type(env_js)=="string", "info table is returned as a string")
ok, info = pcall(json.decode, env_js)
check(ok, "string returned by api.info is json")
check(type(info)=="table", "string returned by api.info decodes into a table")
if type(info)=="table" then
   -- ensure that some key entries are in the table
   check(type(info.ROSIE_VERSION)=="string")
   check(type(info.ROSIE_HOME)=="string")
   check(type(info.ROSIE_LIB)=="string")
   check(type(info.ROSIE_DEV)=="string")
   check(info.ROSIE_DEV=="true")
   check(info.RPL_VERSION:find("1.1"))
end

----------------------------------------------------------------------------------------
heading("Engine")
----------------------------------------------------------------------------------------
subheading("initialize")

ok = wapi.finalize();
check(ok, "finalizing should succeed whether api is initialized or not")

check(type(wapi.initialize)=="function")
ok, msg = wapi.initialize()
check(ok, msg)

ok, msg = wapi.initialize()
check(not ok)
check(msg:find("already"))

ok = wapi.finalize();
check(ok)

ok, eid = wapi.initialize()
check(ok)
check(type(eid)=="string", "engine id returned is a " .. type(eid))

-- N.B. The api does not expose engine.name or engine.id because there is only one engine in the
-- external api.  It is created when a user program/thread calls api.initialize().

subheading("lookup")
check(type(wapi.engine_lookup)=="function")
ok, env_js = wapi.engine_lookup(json.encode(nil)) -- null
check(ok)
check(type(env_js)=="string", "environment is returned as a JSON string")
ok, env = pcall(json.decode, env_js)
check(ok)
check(type(env)=="table")
check(env["."].type=="pattern" and (not env["."].capture), "env contains built-in alias '.'")
check(env["$"].type=="pattern" and (not env["$"].capture), "env contains built-in alias '$'")
ok, msg = wapi.engine_lookup("hello")
check(not ok)
check(msg:find("not a json", 1, true))

subheading("lookup to look at individual bindings")
check(type(wapi.engine_lookup)=="function")
ok, msg = wapi.engine_lookup()
check(not ok)
check(msg:find("not a json", 1, true))
ok, msg = wapi.engine_lookup("hello")
check(not ok)
check(msg:find("not a json", 1, true))
ok, def = wapi.engine_lookup(json.encode("$"))
check(ok, "can get a definition for '$'")
check(json.decode(def).binding:find("built-in RPL pattern", 1, true))

----------------------------------------------------------------------------------------
heading("Load")
----------------------------------------------------------------------------------------
subheading("engine.load")
check(type(wapi.load)=="function")
ok, success, pkg, warning = wapi.load()
check(not ok)					    -- called 'load' incorrectly
check(success:find("not a string", 1, true))
ok, success, pkg, warning = wapi.load("foo")
check(ok) 
check(not success)
check(warning:find("Syntax error at line 1: foo"))
ok, success, pkg, warning = wapi.load('foo = "a"')
check(ok)
check(success)
check(type(pkg)=="string")
pkg = json.decode(pkg)
check(pkg == json.null)
ok, success, pkg, warning = wapi.load('foo = "a"')
check(ok, "assignment did not load, returned: " .. tostring(msg))
check(success)
pkg = json.decode(pkg)
check(pkg == json.null)
check(warning:find("reassignment to identifier"))
ok, env_js = wapi.engine_lookup("null")
check(ok)
env = json.decode(env_js)
check(env["foo"].type=="pattern" and env["foo"].capture, "env contains newly defined identifier")

ok, def = wapi.engine_lookup(json.encode("foo"))
check(ok, "can get a definition for foo that includes a binding")
check(json.decode(def).binding:find("foo", 1, true))

ok, success, pkg, msg = wapi.load('bar = foo / ( "1" $ )')
check(ok and success)
check(type(msg)=="string")
ok, env_js = wapi.engine_lookup("null")
check(ok)
env = json.decode(env_js)
check(type(env)=="table")
check(env["bar"])
check(env["bar"].type=="pattern" and env["bar"].capture, "env contains newly defined identifier")
ok, def = wapi.engine_lookup(json.encode("bar"))
check(ok)
def = json.decode(def)
check(def)
check(type(def)=="table")
check(def.binding:find('CAPTURE as bar:'), "checking binding defn which relies on reveal_ast")
ok, success, pkg, msg = wapi.load('x = //')
check(ok)
check(not success)
check(msg:find("Syntax error at line 1"), "Exact message depends on syntax error reporting")
ok, env_js = wapi.engine_lookup("null")
check(ok)
env = json.decode(env_js)
check(not env["x"])

for _, exp in ipairs{"[0-9]", "[abcdef123]", "[:alpha:]", 
		     "[^0-9]", "[^abcdef123]", "[:^alpha:]", 
		     "[^[a][b]]"} do
   local ok, success, pkg, msg = wapi.load('csx = '..exp)
   check(ok and success)
   --io.write("\n*****   ", tostring(ok), "  ", tostring(msg), "   *****\n")
   ok, msg = wapi.engine_lookup(json.encode("csx"))
   check(ok, "call to lookup failed (cs was bound to " .. exp .. ")")
   local def = json.decode(msg)
   if check(def, "Definition returned from lookup was null") then
      check(def.binding:find(exp, 1, true), "failed to observe this in binding of cs: " .. exp)
   end
end

ok, success, pkg, jsonmsgs = wapi.load('-- comments and \n -- whitespace\t\n\n')
-- "an empty list of ast's is the result of parsing comments and whitespace"
check(ok and success)
msgs = json.decode(jsonmsgs)
check(type(msgs)=="table")
check(type(msgs[1])=="table" and not msgs[2])
check(msgs[1].message:find("Empty input"))

g = [[grammar
  S = {"a" B} / {"b" A} / "" 
  A = {"a" S} / {"b" A A}
  B = {"b" S} / {"a" B B}
end]]

ok, success, pkg, msg = wapi.load(g)
check(ok)
check(type(pkg)=="string")

ok, def = wapi.engine_lookup(json.encode("S"))
check(ok)
def = json.decode(def)
check(def.binding:find('S = CAPTURE as S: {(\"a\" B)', 1, true))
check(def.binding:find('A = CAPTURE as A: {(\"a\" S)', 1, true))
check(def.binding:find('B = CAPTURE as B: {(\"b\" S)', 1, true))

ok, env_js = wapi.engine_lookup("null")
check(ok)
check(type(env_js)=="string", "environment is returned as a JSON string")
env = json.decode(env_js)
check(env["S"].type=="pattern" and env["S"].capture, "type of grammar is reported by lookup() as a definition")

g2_defn = [[grammar
  alias g2 = S ~
  alias S = { {"a" B} / {"b" A} / "" }
  alias A = { {"a" S} / {"b" A A} }
  alias B = { {"b" S} / {"a" B B} }
end]]

ok, success, pkg, msg = wapi.load(g2_defn)
check(ok and success)
check(type(pkg)=="string")

ok, env_js = wapi.engine_lookup("null")
check(ok)
check(type(env_js)=="string", "environment is returned as a JSON string")
env = json.decode(env_js)
check(env["g2"].type=="pattern" and not env["g2"].capture)


subheading("clear")
check(type(wapi.engine_clear)=="function")
ok, msg = wapi.engine_clear()
check(not ok)
ok, msg = wapi.engine_clear("null")	    -- json-encoded arg
check(ok)
check(msg=="true")

ok, env_js = wapi.engine_lookup("null")
check(ok)
check(type(env_js)=="string", "environment is returned as a JSON string")
env = json.decode(env_js)
check(not (env["S"]))
check((env["."]))

subheading("loadfile")
check(type(wapi.loadfile)=="function")
ok, success, pkg, msg = wapi.loadfile()
check(not ok)
check(success:find("not a string"))
ok, success, pkg, msg, path = wapi.loadfile("hellothereisnosuchfileasthis")
check(ok)
check(not success)
check(msg:find("cannot open file"))

ok, success, pkg, msgs, fullpath = wapi.loadfile(ROSIE_HOME .. "/test/ok.rpl")
check(ok)
check(type(pkg)=="string")
check(type(msgs)=="string")
check(type(fullpath)=="string")
check(fullpath:sub(-11)=="test/ok.rpl")
ok, env = wapi.engine_lookup(json.encode(nil))
check(ok)
j = json.decode(env)
env = j
check(env["num"].type=="pattern" and env["num"].capture)
check(env["S"].type=="pattern" and (not env["S"].capture))
ok, def = wapi.engine_lookup(json.encode("W"))
check(ok)
def = json.decode(def)
check(def.binding:find("(!w any)", 1, true), "checking binding defn which relies on reveal_ast")

ok, msg = wapi.engine_clear(json.encode("W"))
check(ok)
check(msg=="true")
ok, msg = wapi.engine_clear(json.encode("W"))
check(ok)
check(msg=="false")
ok, def = wapi.engine_lookup(json.encode("W"))
check(ok)
def = json.decode(def)
check(def==json.null)
-- let's ensure that something in the env remains
ok, def = wapi.engine_lookup(json.encode("num"))
check(ok)
def = json.decode(def)
check(def.binding)

ok, success, pkg, msg = wapi.loadfile("test/undef.rpl", true)
check(ok)
check(not success)
check(msg:find("reference to undefined identifier: spaces"))
--check(msg:find("At line 10"))
ok, env_js = wapi.engine_lookup("null")
check(ok)
env = json.decode(env_js)
check(not env["badword"], "an identifier that didn't compile should not end up in the environment")
check(env["undef"], "definitions in a file prior to an error will end up in the environment... (sigh)")
check(not env["undef2"], "definitions in a file after to an error will NOT end up in the environment")
ok, success, pkg, msg = wapi.loadfile("test/synerr.rpl", true)
check(ok)
check(not success)
check(msg:find('Syntax error at line 9'), "Exact message depends on syntax error reporting")
check(msg:find('foo = \\"foobar\\" \\/\\/'), "relies on reveal_ast")

ok, success, pkg, msg, path = wapi.loadfile("./thisfile/doesnotexist", "rpl")
check(ok)
check(not success)
check(msg:find("cannot open file"))
check(msg:find("./thisfile/doesnotexist"))

ok, success, pkg, msg = wapi.loadfile("/etc", "rpl")
check(ok)
check(not success)
check(msg:find("cannot read file"))
check(msg:find("/etc"))

ok, success, pkg, msg = wapi.loadfile("test/rpl-decl-2.0.rpl", true)
check(ok)
check(not success)
check(msg:find("requires version 2.0"), "rpl version mismatch NOT detected: msg = " .. msg)
check(msg:find("at version 1"), "rpl version mismatch NOT detected: msg = " .. msg)

ok, success, pkg, msg = wapi.loadfile("test/rpl-decl-1.8.rpl", true)
check(ok)
check(not success)
check(msg:find("requires version 1.8"))
check(msg:find("at version 1"))

ok, success, pkg, msg = wapi.loadfile("test/rpl-decl-1.0.rpl", true)
check(ok and success)
--check(msg:find("Warning: reassignment"))

ok, success, pkg, msg = wapi.loadfile("test/rpl-decl-0.5.rpl", true)
check(ok and success)
--check(msg:find("Warning: reassignment"))

ok, success, pkg, msg = wapi.loadfile("test/rpl-decl-0.0.rpl", true)
check(ok and success)
--check(msg:find("Warning: reassignment"))


----------------------------------------------------------------------------------------
--heading("Set output encoder")
--   Currently, the external API gets json formatted match data only
----------------------------------------------------------------------------------------

----------------------------------------------------------------------------------------
heading("Compile expressions and use them")
----------------------------------------------------------------------------------------

subheading("compile")
check(type(wapi.compile)=="function")
ok, msg = wapi.compile()
check(not ok)
check(msg:find("not a string"), "wrong compiler error msg: " .. tostring(msg))

io.write("  ** NEED RPLX TESTS! **  ")

----------------------------------------------------------------------------------------
heading("Match, eval using rpl expressions")
----------------------------------------------------------------------------------------

ok, msg = wapi.match()
check(not ok)
check(msg:find("not a string"))

ok, success, pkg, msgs = wapi.load("import common, num")
check(ok)
check(success)

ok, m, leftover, msgs = wapi.match("common.dotted_id", "x.y.z")
check(ok)
check(type(m)=="userdata")
str = lpeg.getdata(m)
check(type(str)=="string")
match = json.decode(str)
check(type(match)=="table")

check(match.type=="common.dotted_id")
check(match.data=="x.y.z")
check(match.subs[2].data=="y")

subheading("match")
ok, results, left = wapi.match("num.any", "x.y.z")
check(ok)
check(results==false)
check(left=="5")

ok, jsmatch, left = wapi.match('"☯"+~', "☯☯☯"..string.char(10))    -- newline is escaped in json encoding
check(ok)
check(type(jsmatch)=="userdata")
jsmatch = lpeg.getdata(jsmatch)
check(jsmatch:sub(-4)=="\\n\"}")
ok, match = pcall(json.decode, jsmatch)
check(ok)
if ok then
   table.print(match)
   check(match.data==("☯☯☯"..string.char(10)))
   check(match.pos==1)
   check(match["end"]==11)		      -- 3 symbols at 3 bytes each, plus a newline, plus 1
   check(match.type=="*")
end
check(left=="0")


subheading("file match")
check(type(wapi.matchfile)=="function")
ok, msg = wapi.matchfile()
check(not ok)
check(msg:find("Expression not a string"))

ok, msg = wapi.matchfile("num.any")
check(not ok)
check(msg:find("bad input file name"))

ok, msg = wapi.matchfile("num.any", "foo")
check(not ok)
check(msg:find("Unknown flavor"))

ok, msg = wapi.matchfile("num.any", "match", ROSIE_HOME.."/test/test-input")
check(not ok)
check(msg:find("bad output file name"))

ok, msg = wapi.matchfile("num.any", "match", "thisfiledoesnotexist", "", "")
check(not ok, "can't match against nonexistent file")
check(msg:find("No such file or directory"))

ok, msg = wapi.load("import date, time, common")
check(ok)

macosx_log1 = [=[
      date.std_US
      time.time
      common.id
      common.dotted_id
      "[" [[:digit:]]+ "]"
      "(" common.dotted_id {"["[[:digit:]]+"]"}? "):" .*
      ]=]

ok, c_in, c_out, c_err = wapi.matchfile(macosx_log1, "match", ROSIE_HOME.."/test/test-input", "/tmp/out", "/dev/null")
check(ok, "the macosx log pattern in the test file works on some log lines")
c_in = tonumber(c_in); c_out = tonumber(c_out); c_err = tonumber(c_err); 
check(c_in==4 and c_out==2 and c_err==2, "ensure processing of first lines of test-input")

local function check_output_file()
   -- check the structure of the output file
   local nextline = io.lines("/tmp/out")
   for i=1, c_out do
      local l = nextline()
      local j = json.decode(l)
      check(j.type=="*", "the json match in the output file is tagged with a star")
      check(j.data:find("apple"), "the match in the output file is probably ok")
      local c=0
      for k,v in pairs(j.subs) do c=c+1; end
      check(c==5, "the match in the output file has 5 submatches as expected")
   end   
   check(not nextline(), "only two lines of json in output file")
end

if ok then check_output_file(); end

ok, c_in, c_out, c_err = wapi.matchfile(macosx_log1, "match", ROSIE_HOME.."/test/test-input", "/tmp/out", "/tmp/err")
check(ok)
c_in = tonumber(c_in); c_out = tonumber(c_out); c_err = tonumber(c_err);
check(c_in==4 and c_out==2 and c_err==2, "ensure processing of error lines of test-input")

local function check_error_file()
   -- check the structure of the error file
   local nextline = io.lines("/tmp/err")
   for i=1,c_err do
      local l = nextline()
      check(l:find("MUpdate"), "reading contents of error file")
   end   
   check(not nextline(), "only two lines in error file")
end

if ok then check_error_file(); check_output_file(); end

local function clear_output_and_error_files()
   local f=io.open("/tmp/out", "w")
   f:close()
   local f=io.open("/tmp/err", "w")
   f:close()
end

clear_output_and_error_files()
io.write("\nTesting output to stdout:\n")
ok, c_in, c_out, c_err = wapi.matchfile(macosx_log1, "match", ROSIE_HOME.."/test/test-input", "", "/tmp/err")
io.write("\nEnd of output to stdout\n")
check(ok)
c_in = tonumber(c_in); c_out = tonumber(c_out); c_err = tonumber(c_err);
check(c_in==4 and c_out==2 and c_err==2, "ensure processing of all lines of test-input")

if ok then
   -- check that output file remains untouched
   nextline = io.lines("/tmp/out")
   check(not nextline(), "ensure output file still empty")
   check_error_file()
end

clear_output_and_error_files()
io.write("\nTesting output to stderr:\n")
ok, c_in, c_out, c_err = wapi.matchfile(macosx_log1, "match", ROSIE_HOME.."/test/test-input", "/tmp/out", "")
io.write("\nEnd of output to stderr\n")
check(ok)
c_in = tonumber(c_in); c_out = tonumber(c_out); c_err = tonumber(c_err);
check(c_in==4 and c_out==2 and c_err==2, "ensure processing of all lines of test-input")

if ok then
   -- check that error file remains untouched
   nextline = io.lines("/tmp/err")
   check(not nextline(), "ensure error file still empty")
   check_output_file()
end

print("\n\n** SKIPPING eval tests **\n\n")

--[==[

subheading("eval")

check(type(wapi.tracematch)=="function")
ok, msg = wapi.tracematch()
check(not ok)
check(msg:find("Input not a string"))

ok, results = wapi.tracematch(".*//", "foo")
check(not ok)
check(results:find("Syntax error at line 1"))

ok, results_js, leftover, trace = wapi.tracematch(".*", "foo")
check(ok)
results = json.decode(lpeg.getdata(results_js))
check(results)
check(results.type=="*")
check(type(trace)=="string")
check(leftover=="0")
check(trace:find('Matched "foo" %(against input "foo"%)')) -- % is esc char

ok, results, leftover, trace = wapi.tracematch("[[:digit:]]", "foo")
check(ok)
check(not results)
check(leftover=="1")
check(trace:find('FAILED to match against input "foo"'))

ok, results_js, leftover, trace = wapi.tracematch("[[:alpha:]]*", "foo56789")
check(ok)
results = json.decode(lpeg.getdata(results_js))
check(results)
check(results.type=="*")
check(leftover=="5")
check(trace:find('Matched "foo" %(against input "foo56789"%)')) -- % is esc char

ok, results_js, leftover, trace = wapi.tracematch("num.any", "abc.x")
check(ok)
results = json.decode(lpeg.getdata(results_js))
check(results)
check(leftover=="2")				    -- leftover
check(results.type=="num.any")
check(results.data=="abc")
check(trace:find('Matched "abc" %(against input "abc.x"%)')) -- % is esc char

subheading("trace file (was eval_file)")
check(type(wapi.tracematchfile)=="function")
ok, msg = wapi.tracematchfile()
check(not ok)
check(msg:find("Expression not a string"))

ok, msg = wapi.tracematchfile("foo")
check(not ok)
check(msg:find("undefined identifier"))

ok, msg = wapi.tracematchfile(".")
check(not ok)
check(msg:find("bad input file name"))

ok, results_js, leftover, trace = wapi.tracematch(".*", "foo")
check(ok)
if ok then
   match = json.decode(lpeg.getdata(results_js))
   check(match)
   check(match.type=="*")
   check(leftover=="0")
   check(trace:find('Matched "foo" %(against input "foo"%)')) -- % is esc char
end

ok, results_js, leftover, trace = wapi.tracematch("[[:digit:]]", "foo")
check(ok)
if ok then
   check(not results_js)
   check(leftover=="1")
   check(trace:find('FAILED to match against input "foo"')) -- % is esc char
end

ok, c_in, c_out, c_err = wapi.tracematchfile(macosx_log1, "match", ROSIE_HOME.."/test/test-input", "/tmp/out", "/dev/null")
check(ok, "the macosx log pattern in the test file works on some log lines")
check(c_in==4 and c_out==2 and c_err==2, "ensure that output was written for all lines of test-input")

local function check_eval_output_file()
   -- check the structure of the output file: 2 traces of matches, 2 traces of failed matches
   nextline = io.lines("/tmp/out")
   for i=1,4 do
      local l = nextline()
      check(l:find("SEQUENCE: basic.datetime_patterns{2,2}"), "the eval output starts out correctly")
      l = nextline()
      if i<3 then 
	 check(l:find('Matched'), "the eval output for a match continues correctly")
	 l = nextline(); while not l:find("27%.%.%.%.%.") do l = nextline(); end
	 l = nextline()
	 check(l:find('Matched "Service'), "the eval output's last match step looks good")
      else
	 check(l:find("FAILED to match against input"), "the eval output failed match continues correctly")
	 l = nextline(); while not l:find("10%.%.%.%.%.") do print(l); l = nextline(); end
	 l = nextline()
	 print(l)
	 check(l:find("FAILED to match against input"), "the eval output's last fail step looks good")
      end   
      l = nextline()				    -- blank
      if i<3 then
	 l = nextline();
	 local t = json.decode(l);		    -- match
      end
      l = nextline();			    -- blank
   end -- for loop
   check(not nextline(), "exactly 4 eval traces in output file")
end

ok, msg = wapi.tracematchfile(".", "match", ROSIE_HOME.."/test/test-input")
check(not ok)
check(msg:find(": bad output file name"))

ok, msg = wapi.tracematchfile(".", "abcdef", "thisfiledoesnotexist", "", "")
check(not ok)
check(msg:find("Unknown flavor"))

ok, msg = wapi.tracematchfile(".", "match", "thisfiledoesnotexist", "", "")
check(not ok)
check(msg:find("No such file or directory"), "can't match against nonexistent file")

ok, c_in, c_out, c_err = wapi.tracematchfile(macosx_log1, "match", ROSIE_HOME.."/test/test-input", "/tmp/out", "/dev/null")
check(ok, "the macosx log pattern in the test file works on some log lines")
check(c_in==4 and c_out==2 and c_err==2, "ensure that output was written for all lines of test-input")

--]==]


return test.finish()
