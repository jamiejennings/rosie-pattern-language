-- -*- Mode: Lua; -*-                                                                             
--
-- c1.lua    rpl compiler internals for rpl 1.1
--
-- © Copyright IBM Corporation 2017.
-- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
-- AUTHOR: Jamie A. Jennings

local c1 = {}
local c0 = require "c0"

local string = require "string"
local lpeg = require "lpeg"
local common = require "common"
local decode_match = common.decode_match

function c1.process_package_decl(ast, gmr, source, env)
   local typ, pos, text, subs, fin = decode_match(ast)
   assert(typ=="package_decl")
   local typ, pos, text, subs, fin = decode_match(subs[1])
   assert(typ=="packagename")
   print("->", "package = " .. text)
end

function c1.process_language_decl(ast, gmr, source, env)
   local typ, pos, text, subs, fin = decode_match(ast)
   assert(typ=="language_decl")
   local typ, pos, text, subs, fin = decode_match(subs[1])
   assert(typ=="version_spec")
   print("->", "language = " .. text:sub(1,-2))
end

function c1.process_import_decl(ast, gmr, source, env)
   local specs = ast.subs
   for _,spec in ipairs(specs) do
      io.write("*\t", "import ", spec.subs[1].text)
      local packagenamesub = spec.subs[2]
      if packagenamesub then
	 local key = packagenamesub.type	    -- dot or packagename
	 io.write(" as ", packagenamesub.text)
      end
      io.write('\n')
   end -- for
end

function c1.compile_local(ast, gmr, source, env)
   local name = ast.subs[1].type
   print("->", "local " .. name .. ": " .. ast.subs[1].text)
end

function c1.compile_ast(ast, source, env)
   assert(type(ast)=="table", "Compiler: first argument not an ast: "..tostring(ast))
   local functions = {"compile_ast";
		      package_decl = c1.process_package_decl;
		      language_decl = c1.process_language_decl;
		      import_decl = c1.process_import_decl;
		      local_ = c1.compile_local;
		      binding=c0.compile_binding;
		      new_grammar=c0.compile_grammar;
		      exp=c0.compile_exp;
		      default=c0.compile_exp;
		   }
   return common.walk_ast(ast, functions, false, source, env)
end

return c1
