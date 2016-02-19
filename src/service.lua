---- -*- Mode: Lua; -*- 
----
---- service.lua       A simple network service providing Rosie capabilities
----
---- (c) 2015, Jamie A. Jennings
----

---- N.B.  This is NOT coded defensively.  We assume good client behavior, not mistakes or
---- attacks. 


--    Lua 5.3.1  Copyright (C) 1994-2015 Lua.org, PUC-Rio
--    > dofile("/var/folders/82/cvn_sqmj513499bk8ylk3jjw0000gn/T/lua-283613DK")
--    > s = service.start(8088)
--    > x = service.select(s)
--    > c = service.accept(x)
--    > r = service.read(c)
--    > deep_table_concat_pairs(r)
--    stdin:1: attempt to call a nil value (global 'deep_table_concat_pairs')
--    stack traceback:
--            stdin:1: in main chunk
--            [C]: in ?
--    > require "utils"
--    true
--    > deep_table_concat_pairs(r)
--    [1: "GET / HTTP/1.1", 2: "Host: localhost:8088", 3: "User-Agent: curl/7.43.0", 4: "Accept: */*"]
--    > 

socket = require "socket"			    -- LuaSocket 3.0-rc1 seems to work
json = require "cjson"

service = {}

function service.start(port)
   port = port or 8088
   return socket.bind("localhost", port)	    -- returns a server object
end

function service.select(server)
   local s = socket.select({server}, {}, 30)	    -- using timeout so we can print debugging
                                                    -- info once in a while
   if s[1] then return s[1]; end
   service.select(server)
end

function service.accept(server)
   return server:accept()			    -- returns a client object
end

function service.read(client)
   local l, err = client:receive("*l")
   local lines = {}
   while not err and l~="" do
      table.insert(lines, l)
      l, err = client:receive("*l")
   end
   return err or lines
end

function service.reply(client, code, content)
   if code=="OK" then
      client:send("HTTP/1.0 200 OK\r\n")
      client:send("Server: Rosie\r\n")
      client:send("Content-type: application/json\r\n")
      client:send("Connection: close\r\n\r\n")
      client:send(content)
      client:send("\r\n\r\n")
      client:close()
   else
      error("Unsupported response code: " .. tostring(code))
   end
end

default_request_handler =
   function(request)
      io.write("RECEIVED\n")
      for _,l in ipairs(request) do
	 io.write(l, "\n")
      end
      return "OK", "{}"
   end


function service.run(server, request_handler)
   request_handler = request_handler or default_request_handler
   local s = service.select(server)
   local c = service.accept(s)
   local req = service.read(c)
   local code, content = request_handler(req)
   service.reply(c, code, content)
   service.run(server, request_handler)
end

----------------------------------------------------------------------------------------
-- URL format, according to RFC 2396
--
-- <url> ::= <scheme>://<authority>/<path>;<params>?<query>#<fragment>
-- <authority> ::= <userinfo>@<host>:<port>
-- <userinfo> ::= <user>[:<password>]
-- <path> :: = {<segment>/}<segment>
--
-- Note that the leading '/' in /<path> is considered part of <path>
-----------------------------------------------------------------------------
   