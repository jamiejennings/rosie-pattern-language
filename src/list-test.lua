list = require("list")

-- Not testing: 2
--   apply_at_i
--   validate_structure

-- 5
new, from_table, is = list.new, list.from_table, list.is
is_null, len, equal = list.is_null, list.length, list.equal

a = new()
assert(type(a)=="table")
assert(is(a))
assert(is_null(a))
assert(equal(a, a))
assert(equal(a, new()))

b = new()
assert(is(b))
assert(is_null(b))
assert(equal(a,b))
assert(a ~= b)

c = new(1)
assert(is(c))
assert(not is_null(c))
assert(a ~= c)
assert(not equal(a, c))
assert(equal(c, c))
assert(len(c)==1)
assert(#c==1)

d = new("hi", "bye", 42)
assert(is(d))
assert(not is_null(d))
assert(d ~= c)
assert(not equal(d, c))
assert(equal(d, d))
assert(len(d)==3)
assert(#d==3)

e = from_table({"hi", "bye", 42})
assert(is(e))
assert(not is_null(e))
assert(d ~= e)
assert(equal(d, e))
assert(len(e)==3)
assert(#e==3)

ok = pcall(from_table, nil)
assert(not ok)

-- 3
cons, car, cdr = list.cons, list.car, list.cdr


-- 4
member, append, reverse, last = list.member, list.append, list.reverse, list.last



-- 2
andf, orf = list.andf, list.orf


-- 6
apply, map, foreach, flatten, reduce, filter = list.apply, list.map, list.foreach, list.reduce, list.filter






-- 2
p, ts = list.print, list.tostring



print("Done")
