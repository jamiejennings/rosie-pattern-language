dofile "utf8-range.lua"
dofile "ucd.lua"
dofile "test-utf8-range.lua"
dofile "scripts.lua"

locale= lpeg.locale()
posix_names = {}
for k,v in pairs(locale) do table.insert(posix_names, k) end

print("Posix names:")
for _,name in ipairs(posix_names) do print(name) end