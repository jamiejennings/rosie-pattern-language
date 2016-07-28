
ROSIE_HOME = "/Users/jjennings/Work/Dev/rosie-pattern-language"
dofile(ROSIE_HOME.."/src/bootstrap.lua")

api = require "api"
tbl = api.new_engine("null")
table.print(tbl)
if tbl[1]~=true then
   print "Error"; os.exit(-1)
end
eid = tbl[2]

input = "1239999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999"
   
api.configure_engine(eid, json.encode{expression="[:digit:]+", encode=false})

io.write("Looping...")
io.stdout:flush()
t0=os.clock();
for i=1,1000000 do
   retval = api.match(eid, input);
--   js = json.decode(retval[2]);
end;
t1=os.clock();
print(" done.")
print(t1-t0 .. " sec, measured internally")


