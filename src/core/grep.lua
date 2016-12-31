---- -*- Mode: Lua; -*-                                                                           
----
---- grep.lua    a preview of what RPL macros will be able to do
----
---- © Copyright IBM Corporation 2016.
---- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
---- AUTHOR: Jamie A. Jennings

-- Grep searches a line for all occurrences of a given pattern.  For Rosie to search a line for
-- all occurrences of pattern p, we want to transform p into:  {{!p .}* p}+
-- E.g.
--    bash-3.2$ ./run '{{!int .}* int}+' /etc/resolv.conf 
--    10 0 1 1 
--    2606 000 1120 8152 2 7 6 4 1 
--    bash-3.2$ ./run -json '{{!int .}* int}+' /etc/resolv.conf 
--    {"*":{"pos":1,"text":"nameserver 10.0.1.1","subs":[{"int":{"pos":12,"text":"10","subs":{}}},{"int":{"pos":15,"text":"0","subs":{}}},{"int":{"pos":17,"text":"1","subs":{}}},{"int":{"pos":19,"text":"1","subs":{}}}]}}
--    {"*":{"pos":1,"text":"nameserver 2606:a000:1120:8152:2f7:6fff:fed4:dc1","subs":[{"int":{"pos":12,"text":"2606","subs":{}}},{"int":{"pos":18,"text":"000","subs":{}}},{"int":{"pos":22,"text":"1120","subs":{}}},{"int":{"pos":27,"text":"8152","subs":{}}},{"int":{"pos":32,"text":"2","subs":{}}},{"int":{"pos":34,"text":"7","subs":{}}},{"int":{"pos":36,"text":"6","subs":{}}},{"int":{"pos":44,"text":"4","subs":{}}},{"int":{"pos":48,"text":"1","subs":{}}}]}}
--

local grep = {}

local compile = require "compile"

-- Forthcoming: RPL macros will be implemented as transformations on ASTs, not transformations of
-- RPL source (as in the example below).

function grep.pattern_EXP_to_grep_pattern(pattern_exp, env)
   local env = common.new_env(env)		    -- new scope, which will be discarded
   -- First, we compile the exp in order to give an accurate message if it fails
   local pat, msg = compile.compile_source(pattern_exp, env)
   if not pat then return nil, msg; end
   -- Next, we do what we really need to do in order for the grep option to work
   local pat, msg = compile.compile_source("alias e = " .. pattern_exp, env)
   if not pat then return nil, msg; end
   local pat, msg = compile.compile_source("alias grep = {{!e .}* e}+", env) -- should write gensym
   if not pat then return nil, msg; end
   local pat, msg = compile.compile_match_expression("grep", env)
   if not pat then return nil, msg; end
   return pat
end


return grep
