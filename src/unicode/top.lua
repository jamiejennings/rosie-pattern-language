dofile "utf8-range.lua"
dofile "test-utf8-range.lua"
dofile "ucd.lua"
run()
dofile "scripts.lua"

if false then
   locale= lpeg.locale()
   posix_names = {}
   for k,v in pairs(locale) do table.insert(posix_names, k) end

   print("Posix names:")
   for _,name in ipairs(posix_names) do print(name) end

end