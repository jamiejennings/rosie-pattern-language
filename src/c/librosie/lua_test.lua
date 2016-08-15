
ROSIE_HOME = "/Users/jjennings/Work/Dev/rosie-pattern-language"
dofile(ROSIE_HOME.."/src/bootstrap.lua")

api = require "api"
tbl = api.initialize()
table.print(tbl)
if tbl[1]~=true then
   print "Error"; os.exit(-1)
end
eid = tbl[2]

input1 = "1230000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"
input  = "1239999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999"
   
api.configure_engine(json.encode{expression="[:digit:]+", encode="json"})

save = api.match(input1)

retval = api.match(input);
print("Result of calling match:")
table.print(retval);

for_real = true

print()
io.write("Looping...")
io.stdout:flush()
--t0=os.clock();
M = 1000000
--M = 1
for i=1,5*M do
   if for_real then retval = api.match(input);
   else retval = save;
   end
   js = json.decode(retval[2]);
--   if M==1 then table.print(retval); table.print(js); end
end;
--t1=os.clock();
print(" done.")
--print(t1-t0 .. " sec, measured internally")


