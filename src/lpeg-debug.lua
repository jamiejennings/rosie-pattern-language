---- -*- Mode: Lua; -*-                                                                           
----
---- lpeg-debug.lua    set up development environment with debugging version of lpeg
----
---- © Copyright IBM Corporation 2016, 2017.
---- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
---- AUTHOR: Jamie A. Jennings

-- Assumes that lpeg.so was built with debugging enabled and copied into $ROSIE_HOME/lib/debug/lpeg.so

package.cpath = ROSIE_HOME .. "/lib/debug/?.so;" .. package.cpath
 
temp = package.loaded.lpeg
package.loaded.lpeg = nil
lpegdebug = require "lpeg"
package.loaded.lpeg = temp

