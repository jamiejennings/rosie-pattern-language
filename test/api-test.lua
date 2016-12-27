---- -*- Mode: Lua; -*- 
----
---- test-api.lua
----
---- (c) 2016, Jamie A. Jennings
----

test = require "test-functions"
json = require "cjson"
common = require "common"
pattern = common.pattern

check = test.check
heading = test.heading
subheading = test.subheading

function invalid_id(msg)
   return msg:find("invalid engine id")
end

test.start(test.current_filename())

----------------------------------------------------------------------------------------
heading("Require api")
----------------------------------------------------------------------------------------
module.loaded.api = false			    -- force a re-load of the api
api = load_module "api"

check(type(api)=="table")
check(api.API_VERSION and type(api.API_VERSION=="string"))
check(api.VERSION and type(api.ROSIE_VERSION=="string"))
check(api.HOME and type(api.ROSIE_HOME=="string"))

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

ok, js = wapi.info()
check(ok)
check(type(js)=="string")
ok, api_v = pcall(json.decode, js)
check(ok)
check(type(api_v)=="table")

check(type(api_v.API_VERSION)=="string")
check(type(api_v.RPL_VERSION)=="string")
check(type(api_v.VERSION)=="string")
check(type(api_v.HOME)=="string")


----------------------------------------------------------------------------------------
heading("Engine")
----------------------------------------------------------------------------------------
subheading("initialize")
check(type(wapi.initialize)=="function")
ok, msg = wapi.initialize()
check(ok)

ok, msg = wapi.initialize()
check(not ok)
check(msg:find("already"))

ok = wapi.finalize();
check(ok)

ok, eid = wapi.initialize()
check(ok)
check(type(eid)=="string")


subheading("inspect_engine")
check(type(wapi.inspect_engine)=="function")
ok, info_js = wapi.inspect_engine()
check(ok)
ok, info = pcall(json.decode, info_js)
check(ok)
check(type(info)=="table")
check(info.expression)
check(info.encode==false)
check(info.id==eid)

subheading("get_environment")
check(type(wapi.get_environment)=="function")
ok, env_js = wapi.get_environment(json.encode(nil)) -- null
check(ok)
check(type(env_js)=="string", "environment is returned as a JSON string")
env = json.decode(env_js)
check(type(env)=="table")
check(env["."].type=="alias", "env contains built-in alias '.'")
check(env["$"].type=="alias", "env contains built-in alias '$'")
ok, msg = wapi.get_environment("hello")
check(not ok)
check(msg:find("not json", 1, true))

subheading("get_environment to look at individual bindings")
check(type(wapi.get_environment)=="function")
ok, msg = wapi.get_environment()
check(not ok)
check(msg:find("not json", 1, true))
ok, msg = wapi.get_environment("hello")
check(not ok)
check(msg:find("not json", 1, true))
ok, def = wapi.get_environment(json.encode("$"))
check(ok, "can get a definition for '$'")
check(json.decode(def).binding:find("built-in RPL pattern", 1, true))

----------------------------------------------------------------------------------------
heading("Load")
----------------------------------------------------------------------------------------
subheading("load_string")
check(type(wapi.load_string)=="function")
ok, msg = wapi.load_string()
check(not ok)
check(msg:find("not a string", 1, true))
ok, msg = wapi.load_string("foo")
check(not ok)
check(msg:find("Compile error: reference to undefined identifier: foo"))
ok, msg = wapi.load_string('foo = "a"')
check(ok)
check(not msg)
ok, msg = wapi.load_string('foo = "a"')
check(ok)
check(msg:find("reassignment to identifier"))
ok, env_js = wapi.get_environment("null")
check(ok)
env = json.decode(env_js)
check(env["foo"].type=="definition", "env contains newly defined identifier")

ok, def = wapi.get_environment(json.encode("foo"))
check(ok, "can get a definition for foo that includes a binding")
check(json.decode(def).binding:find("assignment foo =", 1, true))

ok, msg = wapi.load_string('bar = foo / ( "1" $ )')
check(ok)
check(not msg)
ok, env_js = wapi.get_environment("null")
check(ok)
env = json.decode(env_js)
check(type(env)=="table")
check(env["bar"])
check(env["bar"].type=="definition", "env contains newly defined identifier")
ok, def = wapi.get_environment(json.encode("bar"))
check(ok)
def = json.decode(def)
check(def)
check(type(def)=="table")
check(def.binding:find('bar = foo / %('), "checking binding defn which relies on reveal_ast")
ok, msg = wapi.load_string('x = //')
check(not ok)
check(msg:find("Syntax error at line 1"), "Exact message depends on syntax error reporting")
ok, env_js = wapi.get_environment("null")
check(ok)
env = json.decode(env_js)
check(not env["x"])

for _, exp in ipairs{"[0-9]", "[abcdef123]", "[:alpha:]", 
		     "[^0-9]", "[^abcdef123]", "[:^alpha:]", 
		     "[^[a][b]]"} do
   local ok, msg = wapi.load_string('csx = '..exp)
   check(ok)
   --io.write("\n*****   ", tostring(ok), "  ", tostring(msg), "   *****\n")
   ok, msg = wapi.get_environment(json.encode("csx"))
   check(ok, "call to get_environment failed (cs was bound to " .. exp .. ")")
   local def = json.decode(msg)
   if check(def, "Definition returned from get_environment was null") then
      check(def.binding:find(exp, 1, true), "failed to observe this in binding of cs: " .. exp)
   end
end



ok, msg = wapi.load_string('-- comments and \n -- whitespace\t\n\n')
-- "an empty list of ast's is the result of parsing comments and whitespace"
check(ok)
check(not msg)

g = [[grammar
  S = {"a" B} / {"b" A} / "" 
  A = {"a" S} / {"b" A A}
  B = {"b" S} / {"a" B B}
end]]

ok, msg = wapi.load_string(g)
check(ok)
check(not msg)

ok, def = wapi.get_environment(json.encode("S"))
check(ok)
def = json.decode(def)
check(def.binding:find("S = {(\"a\" B)}", 1, true))
check(def.binding:find("A = {(\"a\" S)}", 1, true))
check(def.binding:find("B = {(\"b\" S)}", 1, true))

ok, env_js = wapi.get_environment("null")
check(ok)
check(type(env_js)=="string", "environment is returned as a JSON string")
env = json.decode(env_js)
check(env["S"].type=="definition")

g2_defn = [[grammar
  alias g2 = S ~
  alias S = { {"a" B} / {"b" A} / "" }
  alias A = { {"a" S} / {"b" A A} }
  alias B = { {"b" S} / {"a" B B} }
end]]

ok, msg = wapi.load_string(g2_defn)
check(ok)
check(not msg)

ok, env_js = wapi.get_environment("null")
check(ok)
check(type(env_js)=="string", "environment is returned as a JSON string")
env = json.decode(env_js)
check(env["g2"].type=="alias")


subheading("clear_environment")
check(type(wapi.clear_environment)=="function")
ok, msg = wapi.clear_environment()
check(not ok)
ok, msg = wapi.clear_environment("null")	    -- json-encoded arg
check(ok)
check(msg==true)

ok, env_js = wapi.get_environment("null")
check(ok)
check(type(env_js)=="string", "environment is returned as a JSON string")
env = json.decode(env_js)
check(not (env["S"]))
check((env["."]))

subheading("load_file")
check(type(wapi.load_file)=="function")
ok, msg = wapi.load_file()
check(not ok)
check(msg:find("not a string"))
ok, msg = wapi.load_file("hello")
check(not ok)
check(msg:find("cannot open file"))

results = {wapi.load_file("$sys/test/ok.rpl")}
ok = results[1]
check(ok)
check(type(results[2])=="string")
check((results[2]):sub(-11)=="test/ok.rpl")
ok, env = wapi.get_environment("null")
check(ok)
j = json.decode(env)
env = j
check(env["num"].type=="definition")
check(env["S"].type=="alias")
ok, def = wapi.get_environment(json.encode("W"))
check(ok)
def = json.decode(def)
check(def.binding:find("alias W = (!w any)", 1, true), "checking binding defn which relies on reveal_ast")

ok, msg = wapi.clear_environment(json.encode("W"))
check(ok)
check(msg==true)
ok, msg = wapi.clear_environment(json.encode("W"))
check(ok)
check(msg==false)
ok, def = wapi.get_environment(json.encode("W"))
check(ok)
def = json.decode(def)
check(def==json.null)
-- let's ensure that something in the env remains
ok, def = wapi.get_environment(json.encode("num"))
check(ok)
def = json.decode(def)
check(def.binding)

ok, msg = wapi.load_file("$sys/test/undef.rpl")
check(not ok)
check(msg:find("Compile error: reference to undefined identifier: spaces"))
check(msg:find("At line 10"))
ok, env_js = wapi.get_environment("null")
check(ok)
env = json.decode(env_js)
check(not env["badword"], "an identifier that didn't compile should not end up in the environment")
check(env["undef"], "definitions in a file prior to an error will end up in the environment... (sigh)")
check(not env["undef2"], "definitions in a file after to an error will NOT end up in the environment")
ok, msg = wapi.load_file("$sys/test/synerr.rpl")
check(not ok)
check(msg:find('Syntax error at line 9: // "abc"'), "Exact message depends on syntax error reporting")
check(msg:find('foo = "foobar" // "abc"'), "relies on reveal_ast")

ok, msg = wapi.load_file("./thisfile/doesnotexist")
check(not ok)
check(msg:find("cannot open file"))
check(msg:find("./thisfile/doesnotexist"))

ok, msg = wapi.load_file("/etc")
check(not ok)
check(msg:find("cannot read file"))
check(msg:find("/etc"))

subheading("load_manifest")
check(type(wapi.load_manifest)=="function")
ok, msg = wapi.load_manifest()
check(not ok)
check(msg:find("not a string"))
ok, msg = wapi.load_manifest("hello")
check(not ok)
check(msg:find("Error opening manifest file"))
results = {wapi.load_manifest("$sys/test/manifest")}
ok = results[1]
check(ok)
check(results[2]:sub(-13)=="test/manifest")
ok, env_js = wapi.get_environment("null")
check(ok)
env = json.decode(env_js)
check(env["manifest_ok"].type=="definition")

ok, msg = wapi.load_manifest("$sys/test/manifest.err")
check(not ok)
check(msg[3]:find("Error: cannot open file"))

ok, msg = wapi.load_manifest("$sys/test/manifest.synerr") -- contains a //
check(not ok)
check(msg[3]:find("Error: cannot read file"))


----------------------------------------------------------------------------------------
heading("Match")
----------------------------------------------------------------------------------------

subheading("configure")
check(type(wapi.configure_engine)=="function")
ok, msg = wapi.configure_engine()
check(not ok)
check(msg:find("configuration argument not a string"))

ok, msg = wapi.configure_engine()
check(not ok)
check(msg:find("configuration argument not a string"))

ok, msg = wapi.configure_engine(json.encode({expression="common.dotted_identifier",
					  encode="json"}))
check(not ok)
check(msg:find("reference to undefined identifier: common.dotted_identifier"))

ok, msg = wapi.load_file("$sys/rpl/common.rpl")
check(ok)
ok, msg = wapi.configure_engine(json.encode({expression="common.dotted_identifier",
					  encode=false}))
check(ok)
check(not msg)

ok, msg = wapi.get_environment(json.encode("hex_only")) -- common.rpl
check(ok)
def = json.decode(msg)
check(def.binding:find("hex_only = {[[a-f]] / [[A-F]]}", 1, true))

print(" Need more configuration tests!")

subheading("match")
check(type(wapi.match)=="function")
ok, msg = wapi.match()
check(not ok)
check(msg:find("not a string"))

ok, msg = wapi.match()
check(not ok)
check(msg:find("input argument not a string"))

ok, msg = wapi.load_manifest("$sys/MANIFEST")
check(ok)

results = {wapi.match("x.y.z")}
ok = results[1]
check(ok)
check(type(results[2])=="table")
check(type(results[3])=="string")
check(results[3]=="0")
match = results[2]
--check(match["*"])
--match = retvals["*"].subs[1]
check(match["common.dotted_identifier"].text=="x.y.z")
check(match["common.dotted_identifier"].subs[2]["common.identifier_plus_plus"].text=="y")

ok, msg = wapi.configure_engine(json.encode{expression='common.number', encode=false})
check(ok)

results = {wapi.match("x.y.z")}
ok = results[1]
check(ok, "verifying that the engine exp has been changed by the call to configure")
check(not results[2])
check(results[3]=="5")

subheading("match_file")
check(type(wapi.match_file)=="function")
ok, msg = wapi.match_file()
check(not ok)
check(msg:find("bad input file name"))

ok, msg = wapi.match_file(ROSIE_HOME.."/test/test-input")
check(not ok)
check(msg:find("bad output file name"))

ok, msg = wapi.match_file("thisfiledoesnotexist", "", "")
check(not ok, "can't match against nonexistent file")
check(msg:find("No such file or directory"))

macosx_log1 = [=[
      basic.datetime_patterns{2,2}
      common.identifier_plus_plus
      common.dotted_identifier
      "[" [[:digit:]]+ "]"
      "(" common.dotted_identifier {"["[[:digit:]]+"]"}? "):" .*
      ]=]
ok, msg = wapi.configure_engine(json.encode{expression=macosx_log1, encode="json"})
check(ok)			    
results = {wapi.match_file(ROSIE_HOME.."/test/test-input", "/tmp/out", "/dev/null")}
ok = results[1]
check(ok, "the macosx log pattern in the test file works on some log lines")
retvals = json.decode(results[2])
c_in, c_out, c_err = retvals[1], retvals[2], retvals[3]
check(c_in==4 and c_out==2 and c_err==2, "ensure processing of first lines of test-input")

local function check_output_file()
   -- check the structure of the output file
   local nextline = io.lines("/tmp/out")
   for i=1, c_out do
      local l = nextline()
      local j = json.decode(l)
      check(j["*"], "the json match in the output file is tagged with a star")
      check(j["*"].text:find("apple"), "the match in the output file is probably ok")
      local c=0
      for k,v in pairs(j["*"].subs) do c=c+1; end
      check(c==5, "the match in the output file has 5 submatches as expected")
   end   
   check(not nextline(), "only two lines of json in output file")
end

if ok then check_output_file(); end

results = {wapi.match_file(ROSIE_HOME.."/test/test-input", "/tmp/out", "/tmp/err")}
ok = results[1]
check(ok)
retvals = json.decode(results[2])
c_in, c_out, c_err = retvals[1], retvals[2], retvals[3]
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
results = {wapi.match_file(ROSIE_HOME.."/test/test-input", "", "/tmp/err")}
io.write("\nEnd of output to stdout\n")
ok = results[1]
check(ok)
retvals = json.decode(results[2])
c_in, c_out, c_err = retvals[1], retvals[2], retvals[3]
check(c_in==4 and c_out==2 and c_err==2, "ensure processing of all lines of test-input")

if ok then
   -- check that output file remains untouched
   nextline = io.lines("/tmp/out")
   check(not nextline(), "ensure output file still empty")
   check_error_file()
end

clear_output_and_error_files()
io.write("\nTesting output to stderr:\n")
results = {wapi.match_file(ROSIE_HOME.."/test/test-input", "/tmp/out", "")}
io.write("\nEnd of output to stderr\n")
ok = results[1]
check(ok)
retvals = json.decode(results[2])
c_in, c_out, c_err = retvals[1], retvals[2], retvals[3]
check(c_in==4 and c_out==2 and c_err==2, "ensure processing of all lines of test-input")

if ok then
   -- check that error file remains untouched
   nextline = io.lines("/tmp/err")
   check(not nextline(), "ensure error file still empty")
   check_output_file()
end

print("Starting color output to stdout")
ok, msg = wapi.configure_engine(json.encode{encode="color"})
check(ok)
results = {wapi.match_file(ROSIE_HOME.."/test/test-input", "", "/tmp/err")}
print("End of color output to stdout")
ok = results[1]
check(ok)
retvals = json.decode(results[2])
check(retvals[1]==4 and retvals[2]==2 and retvals[3]==2)

subheading("eval")

check(type(wapi.eval)=="function")
ok, msg = wapi.eval()
check(not ok)
check(msg=="Argument error: input argument not a string")

ok, msg = wapi.configure_engine(json.encode{expression=".*//", encode="json"})
check(not ok)
check(msg:find('Syntax error at line 1:'))

ok = wapi.configure_engine(json.encode{expression=".*", encode="json"})
check(ok)
results = {wapi.eval("foo")}
ok = results[1]
check(ok)
retvals = {table.unpack(results, 2)}
check(retvals[1])
check(retvals[2]=="0")
if check(retvals[3]) then
   check(retvals[3]:find('Matched "foo" %(against input "foo"%)')) -- % is esc char
end

ok, msg = wapi.configure_engine(json.encode{expression="[[:digit:]]", encode="json"})
check(ok)
results = {wapi.eval("foo")}
ok = results[1]
check(ok)
retvals = {table.unpack(results, 2)}
check(not retvals[1])
check(retvals[2]=="3")
if check(retvals[3]) then
   check(retvals[3]:find('FAILED to match against input "foo"'))
end

ok, msg = wapi.configure_engine(json.encode{expression="[[:alpha:]]*", encode="json"})
check(ok)
results = {wapi.eval("foo56789")}
ok = results[1]
check(ok)
retvals = {table.unpack(results, 2)}
check(retvals[1])
check(retvals[2]=="5")
if check(retvals[3]) then
   check(retvals[3]:find('Matched "foo" %(against input "foo56789"%)')) -- % is esc char
end

ok, msg = wapi.configure_engine(json.encode{expression="common.number", encode="json"})
check(ok)
results = {wapi.eval("abc.x")}
ok = results[1]
check(ok)
retvals = {table.unpack(results, 2)}
check(retvals[1])				    -- match string
check(retvals[2]=="2")				    -- leftover
--trace = retvals[3]
--check(match["common.number"])
--check(match["common.number"].text=="abc")
if check(retvals[3]) then
   check(retvals[3]:find('Matched "abc" %(against input "abc.x"%)')) -- % is esc char
end

subheading("eval_file")
check(type(wapi.eval_file)=="function")
ok, msg = wapi.eval_file()
check(not ok)
check(msg:find("bad input file name"))

ok, msg = wapi.configure_engine(json.encode{expression=".*", encode="json"})
check(ok)
results = {wapi.eval("foo")}
ok = results[1]
check(ok)
if ok then
   retvals = {table.unpack(results, 2)}
   match, leftover, msg = retvals[1], retvals[2], retvals[3]
   check(match)
   check(leftover=="0")
   check(msg:find('Matched "foo" %(against input "foo"%)')) -- % is esc char
end

ok, msg = wapi.configure_engine(json.encode{expression="[[:digit:]]", encode="json"})
check(ok)
results = {wapi.eval("foo")}
ok = results[1]
check(ok)
if ok then
   retvals = {table.unpack(results, 2)}
   match, leftover, msg = retvals[1], retvals[2], retvals[3]
   check(not match)
   check(leftover=="3")
   check(msg:find('FAILED to match against input "foo"')) -- % is esc char
end

 ok, msg = wapi.configure_engine(json.encode{expression=macosx_log1, encode="json"})
 check(ok)			    
 results = {wapi.eval_file(ROSIE_HOME.."/test/test-input", "/tmp/out", "/dev/null")}
 ok = results[1]
 check(ok, "the macosx log pattern in the test file works on some log lines")
 retvals = json.decode(results[2])
 c_in, c_out, c_err = retvals[1], retvals[2], retvals[3]
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

ok, msg = wapi.eval_file(ROSIE_HOME.."/test/test-input")
check(not ok)
check(msg:find(": bad output file name"))

ok, msg = wapi.eval_file("thisfiledoesnotexist", "", "")
check(not ok)
check(msg:find("No such file or directory"), "can't match against nonexistent file")

ok, msg = wapi.configure_engine(json.encode{expression=macosx_log1, encode="json"})
check(ok)			    
results = {wapi.eval_file(ROSIE_HOME.."/test/test-input", "/tmp/out", "/dev/null")}
ok = results[1]
check(ok, "the macosx log pattern in the test file works on some log lines")
if ok then
   retvals = json.decode(results[2])
   c_in, c_out, c_err = retvals[1], retvals[2], retvals[3]
   check(c_in==4 and c_out==2 and c_err==2, "ensure that output was written for all lines of test-input")
end

return test.finish()
