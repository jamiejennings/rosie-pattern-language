---- -*- Mode: Lua; -*- 
----
---- test-api.lua
----
---- (c) 2016, Jamie A. Jennings
----

test = require "test-functions"
json = require "cjson"

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
package.loaded.api = false			    -- force a re-load of the api
api = require "api"

check(type(api)=="table")
check(api.API_VERSION and type(api.API_VERSION=="string"))
check(api.ROSIE_VERSION and type(api.ROSIE_VERSION=="string"))
check(api.ROSIE_HOME and type(api.ROSIE_HOME=="string"))

ok, js = api.info()
check(ok)
check(type(js)=="string")
ok, api_v = pcall(json.decode, js)
check(ok)
check(type(api_v)=="table")
check(type(api_v[1])=="table")
api_v = api_v[1]
check(type(api_v.API_VERSION)=="string")
check(type(api_v.RPL_VERSION)=="string")
check(type(api_v.ROSIE_VERSION)=="string")
check(type(api_v.ROSIE_HOME)=="string")


----------------------------------------------------------------------------------------
heading("Engine")
----------------------------------------------------------------------------------------
subheading("new_engine")
check(type(api.new_engine)=="function")
ok, eid_js = api.new_engine(json.encode{name="hello", expression=".*", encode=false})
check(ok)
check(type(eid_js)=="string")
ok, eid = pcall(json.decode, eid_js)
check(ok)
check(type(eid)=="table")
check(type(eid[1])=="string")
eid = eid[1]
ok, msg = api.new_engine(json.encode{name="hello", expression=".*", encode="jsonn"}) -- jsonn
check(not ok)
check(msg:find("invalid encode type"))
ok, eid2_js = api.new_engine(json.encode{name="hello"})
check(ok)
check(type(eid2_js)=="string")
eid2 = json.decode(eid2_js)
check(type(eid2[1])=="string")
eid2 = eid2[1]
check(eid~=eid2, "engine ids (as generated by Lua) must be unique")
ok, msg = api.new_engine()
check(not ok)
check(msg:find("not a json-encoded object", 1, true))
ok, msg = api.new_engine("null")
check(ok)


subheading("inspect_engine")
check(type(api.inspect_engine)=="function")
ok, info_js = api.inspect_engine(eid)
check(ok)
ok, info = pcall(json.decode, info_js)
check(ok)
check(type(info[1])=="table")
check(info[1].name=="hello")
check(info[1].expression)
check(info[1].encode==false)
check(info[1].id==eid)

ok, msg = api.inspect_engine()
check(not ok)
check(invalid_id(msg))
ok, msg = api.inspect_engine("foobar")
check(not ok)
check(invalid_id(msg))

subheading("delete_engine")
check(type(api.delete_engine)=="function")
ok, msg = api.delete_engine(eid2)
check(ok)
check(#(json.decode(msg)) == 0)
ok, msg = api.delete_engine(eid2)
check(ok, "idempotent delete function")
check(#(json.decode(msg)) == 0)

ok, msg = api.inspect_engine(eid2)
check(not ok)
check(invalid_id(msg))
check(api.inspect_engine(eid), "other engine with same name still exists")

subheading("get_environment")
check(type(api.get_environment)=="function")
ok, env_js = api.get_environment(eid)
check(ok)
check(type(env_js)=="string", "environment is returned as a JSON string")
j = json.decode(env_js)
check(type(j)=="table")
check(type(j[1])=="table")
env = j[1]
check(env["."].type=="alias", "env contains built-in alias '.'")
check(env["$"].type=="alias", "env contains built-in alias '$'")
ok, msg = api.get_environment()
check(not ok)
check(invalid_id(msg))
ok, msg = api.get_environment("hello")
check(not ok)
check(invalid_id(msg))

subheading("get_binding")
check(type(api.get_binding)=="function")
ok, msg = api.get_binding()
check(not ok)
check(invalid_id(msg))
ok, msg = api.get_binding("hello")
check(not ok)
check(invalid_id(msg))
ok, def = api.get_binding(eid, "$")
check(ok, "can get a definition for '$'")
check(json.decode(def)[1]:find("built-in RPL pattern", 1, true))

----------------------------------------------------------------------------------------
heading("Load")
----------------------------------------------------------------------------------------
subheading("load_string")
check(type(api.load_string)=="function")
ok, msg = api.load_string()
check(not ok)
check(invalid_id(msg))
ok, msg = api.load_string("hello")
check(not ok)
check(invalid_id(msg))
ok, msg = api.load_string(eid, "foo")
check(not ok)
check(msg:find("Compile error: reference to undefined identifier: foo"))
ok, msg = api.load_string(eid, 'foo = "a"')
check(ok)
check(#json.decode(msg)==0)
ok, msg = api.load_string(eid, 'foo = "a"')
check(ok)
check(json.decode(msg)[1][1]:find("reassignment to identifier"))
ok, env_js = api.get_environment(eid)
check(ok)
env = json.decode(env_js)[1]
check(env["foo"].type=="definition", "env contains newly defined identifier")
ok, msg = api.load_string(eid, 'bar = foo / ( "1" $ )')
check(ok)
check(#json.decode(msg)==0)
ok, env_js = api.get_environment(eid)
check(ok)
env = json.decode(env_js)[1]
check(type(env)=="table")
check(env["bar"])
check(env["bar"].type=="definition", "env contains newly defined identifier")
ok, def = api.get_binding(eid, "bar")
check((json.decode(def)[1]:find('bar = foo / %(')), "checking binding defn which relies on reveal_ast")
ok, msg = api.load_string(eid, 'x = //', "syntax error")
check(not ok)
check(msg:find("Syntax error at line 1"), "Exact message depends on syntax error reporting")
ok, env_js = api.get_environment(eid)
check(ok)
env = json.decode(env_js)[1]
check(not env["x"])

for _, exp in ipairs{"[0-9]", "[abcdef123]", "[:alpha:]", 
		     "[^0-9]", "[^abcdef123]", "[:^alpha:]", 
		     "[^[a][b]]"} do
   ok, msg = api.load_string(eid, 'cs = '..exp)
   check(ok)
   ok, msg = api.get_binding(eid, "cs")
   check(ok, "failed to get binding for cs when it is bound to " .. exp)
   check(json.decode(msg)[1]:find(exp, 1, true), "failed to observe this in binding of cs: " .. exp)
end



ok, msg = api.load_string(eid, '-- comments and \n -- whitespace\t\n\n',
   "an empty list of ast's is the result of parsing comments and whitespace")
check(ok)
check(#json.decode(msg)==0)

g = [[grammar
  S = {"a" B} / {"b" A} / "" 
  A = {"a" S} / {"b" A A}
  B = {"b" S} / {"a" B B}
end]]

ok, msg = api.load_string(eid, g)
check(ok)
check(#json.decode(msg)==0)

ok, def = api.get_binding(eid, "S")
check(ok)
check(json.decode(def)[1]:find("S = {(\"a\" B)}", 1, true))
check(json.decode(def)[1]:find("A = {(\"a\" S)}", 1, true))
check(json.decode(def)[1]:find("B = {(\"b\" S)}", 1, true))

ok, env_js = api.get_environment(eid)
check(ok)
check(type(env_js)=="string", "environment is returned as a JSON string")
env = json.decode(env_js)[1]
check(env["S"].type=="definition")


subheading("clear_environment")
check(type(api.clear_environment)=="function")
ok, msg = api.clear_environment(eid)
check(ok)
check(#json.decode(msg)==0)

ok, env_js = api.get_environment(eid)
check(ok)
check(type(env_js)=="string", "environment is returned as a JSON string")
env = json.decode(env_js)[1]
check(not (env["S"]))
check((env["."]))

subheading("load_file")
check(type(api.load_file)=="function")
ok, msg = api.load_file()
check(not ok)
check(invalid_id(msg))
ok, msg = api.load_file("hello")
check(not ok)
check(invalid_id(msg))

ok, msg = api.load_file(eid, "$sys/test/ok.rpl")
check(ok)
check(type(msg)=="string")
check(json.decode(msg)[2]:sub(-11)=="test/ok.rpl")
ok, env = api.get_environment(eid)
check(ok)
j = json.decode(env)
env = j[1]
check(env["num"].type=="definition")
check(env["S"].type=="alias")
ok, def = api.get_binding(eid, "W")
check(ok)
check(json.decode(def)[1]:find("alias W = (!w any)", 1, true), "checking binding defn which relies on reveal_ast")
ok, msg = api.load_file(eid, "$sys/test/undef.rpl")
check(not ok)
check(msg:find("Compile error: reference to undefined identifier: spaces"))
check(msg:find("At line 9"))
ok, env_js = api.get_environment(eid)
check(ok)
env = json.decode(env_js)[1]
check(not env["badword"], "an identifier that didn't compile should not end up in the environment")
check(env["undef"], "definitions in a file prior to an error will end up in the environment... (sigh)")
check(not env["undef2"], "definitions in a file after to an error will NOT end up in the environment")
ok, msg = api.load_file(eid, "$sys/test/synerr.rpl")
check(not ok)
msg = json.decode(msg)[1]
check(msg:find('Syntax error at line 8: // "abc"'), "Exact message depends on syntax error reporting")
check(msg:find('foo = "foobar" // "abc"'), "relies on reveal_ast")

ok, msg = api.load_file(eid, "./thisfile/doesnotexist")
check(not ok)
msg = json.decode(msg)[1]
check(msg:find("cannot open file"))
check(msg:find("./thisfile/doesnotexist"))

ok, msg = api.load_file(eid, "/etc")
check(not ok)
check(msg:find("cannot read file"))
check(msg:find("/etc"))

subheading("load_manifest")
check(type(api.load_manifest)=="function")
ok, msg = api.get_binding()
check(not ok)
check(invalid_id(msg))
ok, msg = api.get_binding("hello")
check(not ok)
check(invalid_id(msg))
ok, msg = api.load_manifest(eid, "$sys/test/manifest")
check(ok)
check(json.decode(msg)[2]:sub(-13)=="test/manifest")
ok, env_js = api.get_environment(eid)
check(ok)
env = json.decode(env_js)[1]
check(env["manifest_ok"].type=="definition")

ok, msg = api.load_manifest(eid, "$sys/test/manifest.err")
check(not ok)
check(msg:find("Error: cannot open file"))

ok, msg = api.load_manifest(eid, "$sys/test/manifest.synerr") -- contains a //
check(not ok)
check(msg:find("Error: cannot read file"))


----------------------------------------------------------------------------------------
heading("Match")
----------------------------------------------------------------------------------------
-- subheading("match_using_exp")
-- check(type(api.match_using_exp)=="function")
-- ok, msg = api.match_using_exp()
-- check(not ok)
-- check(msg==arg_err_engine_id)

-- ok, msg = api.match_using_exp(eid)
-- check(not ok)
-- check(msg:find("pattern expression not a string"))

-- ok, match, left = api.match_using_exp(eid, ".", "A")
-- check(ok)
-- check(left==0)
-- j = json.decode(match)
-- check(j["*"].text=="A")
-- check(j["*"].pos==1)

-- ok, match, left = api.match_using_exp(eid, '{"A".}', "ABC")
-- check(ok)
-- check(left==1)
-- j = json.decode(match)
-- check(j["*"].text=="AB")
-- check(j["*"].pos==1)

-- ok, msg = api.load_manifest(eid, "MANIFEST")
-- check(ok)

-- ok, match, left = api.match_using_exp(eid, 'common.number', "1FACE x y")
-- check(ok)
-- check(left==3)
-- j = json.decode(match)
-- check(j["common.number"].text=="1FACE")
-- check(j["common.number"].pos==1)

-- ok, match, left = api.match_using_exp(eid, '[:space:]* common.number', "   1FACE")
-- check(ok)
-- check(left==0)
-- j = json.decode(match)
-- check(j["*"].pos==1)
-- check(j["*"].subs[1]["common.number"])
-- check(j["*"].subs[1]["common.number"].pos==4)


subheading("configure")
check(type(api.configure_engine)=="function")
ok, msg = api.configure_engine()
check(not ok)
check(invalid_id(msg))

ok, msg = api.configure_engine(eid)
check(not ok)
check(msg:find("configuration argument not a string"))

ok, msg = api.configure_engine(eid, json.encode({expression="common.dotted_identifier",
					  encode="json"}))
check(not ok)
check(msg:find("reference to undefined identifier: common.dotted_identifier"))

ok, msg = api.load_file(eid, "$sys/rpl/common.rpl")
check(ok)
ok, msg = api.configure_engine(eid, json.encode({expression="common.dotted_identifier",
					  encode=false}))
check(ok)
check(#json.decode(msg)==0)

ok, msg = api.get_binding(eid, "hex_only")	    -- common.rpl
check(ok)
check(json.decode(msg)[1]:find("hex_only = {[[a-f]] / [[A-F]]}", 1, true))

print(" Need more configuration tests!")

subheading("match")
check(type(api.match)=="function")
ok, msg = api.match()
check(not ok)
check(invalid_id(msg))

ok, msg = api.match(eid)
check(not ok)
check(msg:find("input argument not a string"))

ok, msg = api.load_manifest(eid, "$sys/MANIFEST")
check(ok)

ok, retvals_js = api.match(eid, "x.y.z")
check(ok)
check(type(retvals_js)=="string")
retvals = json.decode(retvals_js)
check(retvals[2]==0)
match = retvals[1]
--check(match["*"])
--match = retvals[1]["*"].subs[1]
check(match["common.dotted_identifier"].text=="x.y.z")
check(match["common.dotted_identifier"].subs[2]["common.identifier_plus_plus"].text=="y")

ok, msg = api.configure_engine(eid, json.encode{expression='common.number', encode=false})
check(ok)

ok, retvals_js = api.match(eid, "x.y.z")
check(ok, "verifying that the engine exp has been changed by the call to configure")
retvals = json.decode(retvals_js)
check(not retvals[1])
check(retvals[2]==5)

subheading("match_file")
check(type(api.match_file)=="function")
ok, msg = api.match_file()
check(not ok)
check(invalid_id(msg))
ok, msg = api.match_file(eid)
check(ok)
check(msg:find("bad input file name"))

ok, msg = api.match_file(eid, ROSIE_HOME.."/test/test-input")
check(ok)
check(msg:find("bad output file name"))

ok, msg = api.match_file(eid, "thisfiledoesnotexist", "", "")
check(ok, "can't match against nonexistent file")
check(msg:find("No such file or directory"))

macosx_log1 = [=[
      basic.datetime_patterns{2,2}
      common.identifier_plus_plus
      common.dotted_identifier
      "[" [[:digit:]]+ "]"
      "(" common.dotted_identifier {"["[[:digit:]]+"]"}? "):" .*
      ]=]
ok, msg = api.configure_engine(eid, json.encode{expression=macosx_log1, encode="json"})
check(ok)			    
ok, retvals_js = api.match_file(eid, ROSIE_HOME.."/test/test-input", "/tmp/out", "/dev/null")
check(ok, "the macosx log pattern in the test file works on some log lines")
retvals = json.decode(retvals_js)
c_in, c_out, c_err = retvals[1], retvals[2], retvals[3]
check(c_in==4 and c_out==2 and c_err==2, "ensure processing of first lines of test-input")

local function check_output_file()
   -- check the structure of the output file
   nextline = io.lines("/tmp/out")
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

ok, retvals_js = api.match_file(eid, ROSIE_HOME.."/test/test-input", "/tmp/out", "/tmp/err")
check(ok)
retvals = json.decode(retvals_js)
c_in, c_out, c_err = retvals[1], retvals[2], retvals[3]
check(c_in==4 and c_out==2 and c_err==2, "ensure processing of error lines of test-input")

local function check_error_file()
   -- check the structure of the error file
   nextline = io.lines("/tmp/err")
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
ok, retvals_js = api.match_file(eid, ROSIE_HOME.."/test/test-input", "", "/tmp/err")
io.write("\nEnd of output to stdout\n")
check(ok)
retvals = json.decode(retvals_js)
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
ok, retvals_js = api.match_file(eid, ROSIE_HOME.."/test/test-input", "/tmp/out", "")
io.write("\nEnd of output to stderr\n")
check(ok)
retvals = json.decode(retvals_js)
c_in, c_out, c_err = retvals[1], retvals[2], retvals[3]
check(c_in==4 and c_out==2 and c_err==2, "ensure processing of all lines of test-input")

if ok then
   -- check that error file remains untouched
   nextline = io.lines("/tmp/err")
   check(not nextline(), "ensure error file still empty")
   check_output_file()
end

print("Starting color output to stdout")
ok, msg = api.configure_engine(eid, json.encode{encode="color"})
check(ok)
ok, retvals_js = api.match_file(eid, ROSIE_HOME.."/test/test-input", "", "/tmp/err")
print("End of color output to stdout")
check(ok)
retvals = json.decode(retvals_js)
check(retvals[1]==4 and retvals[2]==2 and retvals[3]==2)

subheading("eval")

check(type(api.eval)=="function")
ok, msg = api.eval()
check(not ok)
check(invalid_id(msg))
ok, msg = api.eval(eid)
check(not ok)
check(json.decode(msg)[1]=="Argument error: input argument not a string")

ok, msg = api.configure_engine(eid, json.encode{expression=".*//", encode="json"})
check(not ok)
check(msg:find('Syntax error at line 1:'))

ok, msg = api.configure_engine(eid, json.encode{expression=".*", encode="json"})
check(ok)
ok, retvals_js = api.eval(eid, "foo")
check(ok)
retvals = json.decode(retvals_js)
check(retvals[1])
check(retvals[2]==0)
check(retvals[3]:find('Matched "foo" %(against input "foo"%)')) -- % is esc char

ok, msg = api.configure_engine(eid, json.encode{expression="[[:digit:]]", encode="json"})
check(ok)
ok, retvals_js = api.eval(eid, "foo")
check(ok)
retvals = json.decode(retvals_js)
check(not retvals[1])
check(retvals[2]==3)
check(retvals[3]:find('FAILED to match against input "foo"'))

ok, msg = api.configure_engine(eid, json.encode{expression="[[:alpha:]]*", encode="json"})
check(ok)
ok, retvals_js = api.eval(eid, "foo56789")
check(ok)
retvals = json.decode(retvals_js)
check(retvals[1])
check(retvals[2]==5)
check(retvals[3]:find('Matched "foo" %(against input "foo56789"%)')) -- % is esc char

ok, msg = api.configure_engine(eid, json.encode{expression="common.number", encode="json"})
check(ok)
ok, retvals_js = api.eval(eid, "abc.x")
check(ok)
retvals = json.decode(retvals_js)
check(retvals[1])				    -- match string
check(retvals[2]==2)				    -- leftover
--trace = retvals[3]
--check(match["common.number"])
--check(match["common.number"].text=="abc")
check(retvals[3]:find('Matched "abc" %(against input "abc.x"%)')) -- % is esc char

subheading("eval_file")
check(type(api.eval_file)=="function")
ok, msg = api.eval_file()
check(not ok)
check(invalid_id(msg))
ok, msg = api.eval_file(eid)
check(ok)
check(msg:find(": bad input file name"))

ok, msg = api.configure_engine(eid, json.encode{expression=".*", encode="json"})
check(ok)
ok, retvals_js = api.eval(eid, "foo")
check(ok)
if ok then
   retvals = json.decode(retvals_js)
   match, leftover, msg = retvals[1], retvals[2], retvals[3]
   check(match)
   check(leftover==0)
   check(msg:find('Matched "foo" %(against input "foo"%)')) -- % is esc char
end

ok, msg = api.configure_engine(eid, json.encode{expression="[[:digit:]]", encode="json"})
check(ok)
ok, retvals_js = api.eval(eid, "foo")
check(ok)
if ok then
   retvals = json.decode(retvals_js)
   match, leftover, msg = retvals[1], retvals[2], retvals[3]
   check(not match)
   check(leftover==3)
   check(msg:find('FAILED to match against input "foo"')) -- % is esc char
end

 ok, msg = api.configure_engine(eid, json.encode{expression=macosx_log1, encode="json"})
 check(ok)			    
 ok, retvals_js = api.eval_file(eid, ROSIE_HOME.."/test/test-input", "/tmp/out", "/dev/null")
 check(ok, "the macosx log pattern in the test file works on some log lines")
 retvals = json.decode(retvals_js)
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

ok, msg = api.eval_file(eid, ROSIE_HOME.."/test/test-input")
check(ok)
check(msg:find(": bad output file name"))

ok, msg = api.eval_file(eid, "thisfiledoesnotexist", "", "")
check(ok)
check(msg:find("No such file or directory"), "can't match against nonexistent file")

ok, msg = api.configure_engine(eid, json.encode{expression=macosx_log1, encode="json"})
check(ok)			    
ok, retvals_js = api.eval_file(eid, ROSIE_HOME.."/test/test-input", "/tmp/out", "/dev/null")
check(ok, "the macosx log pattern in the test file works on some log lines")
if ok then
   retvals = json.decode(retvals_js)
   c_in, c_out, c_err = retvals[1], retvals[2], retvals[3]
   check(c_in==4 and c_out==2 and c_err==2, "ensure that output was written for all lines of test-input")
end

return test.finish()

