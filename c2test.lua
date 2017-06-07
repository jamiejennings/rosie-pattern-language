rosie = require "rosie"
e = rosie.engine.new()

util = rosie._env.util
common = rosie._env.common
environment = rosie._env.environment
ast = rosie._env.ast
loadpkg = rosie._env.loadpkg

e:load("import rosie/rpl_1_1 as .")
c = {}
c.parse_block = function(src)
		   print("load: entering parse_block")
		   local maj, min, start = e.compiler.parser.preparse(src)
		   if not maj then error("preparse failed"); end
		   local ok, pt, leftover = e:match("rpl_statements", src, start)
		   -- TODO: syntax error check
		   return pt, {}, leftover	    -- no warnings for now
		 end

c.expand_block = function(a, env, messages)
   -- ... TODO ...
   print("load: dummy expand_block function called with argument " .. tostring(a))
   return true
end

c.compile_block = function(...)
		      print("load: dummy compile_block called")
		      return true
		   end


messages = {}
pkgtable = environment.make_module_table()
env = environment.new()

function dump_state()
   print("Pkgtable:")
   for k,v in pairs(pkgtable) do print(k,v); end
   print("Top level env:")
   for k,v in env:bindings() do print(k,v); end
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

go("import net, common as .")
go("import common")


