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

function go(importpath)
   print("Loading " .. importpath)
   fullpath, src, errmsg = common.get_file(importpath, e.searchpath)
   if (not src) then error("go: failed to find import " .. importpath); end
   loadpkg.source(c, pkgtable, e.searchpath, src, importpath, fullpath, messages)
   for k,v in pairs(pkgtable) do print(k,v); end
end

go("num")
go("net")
