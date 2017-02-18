list = require("list")

-- Not testing: 2
--   apply_at_i
--   validate_structure

-- 5
new, from, is = list.new, list.from, list.is
null, len, equal = list.null, list.length, list.equal

a = new()
assert(type(a)=="table")
assert(is(a))
assert(null(a))
assert(equal(a, a))
assert(equal(a, new()))

b = new()
assert(is(b))
assert(null(b))
assert(equal(a,b))
assert(a ~= b)

c = new(1)
assert(is(c))
assert(not null(c))
assert(a ~= c)
assert(not equal(a, c))
assert(equal(c, c))
assert(len(c)==1)
assert(#c==1)

d = new("hi", "bye", 42)
assert(is(d))
assert(not null(d))
assert(d ~= c)
assert(not equal(d, c))
assert(equal(d, d))
assert(len(d)==3)
assert(#d==3)

e = from({"hi", "bye", 42})
assert(is(e))
assert(not null(e))
assert(d ~= e)
assert(equal(d, e))
assert(len(e)==3)
assert(#e==3)

ok = pcall(from, nil)
assert(not ok)

a = from({})
assert(type(a)=="table")
assert(is(a))
assert(null(a))
assert(equal(a, a))
assert(equal(a, new()))


-- 3
cons, car, cdr = list.cons, list.car, list.cdr

b = cons("new element", a)
assert(is(b))
assert(not null(b))
assert(b ~= a)
assert(not equal(b, a))
assert(len(b)==1)
assert(#b==1)

c = cons("new element", a)
assert(is(c))
assert(not null(c))
assert(c ~= b)
assert(equal(c, b))
assert(len(c)==1)
assert(#c==1)

c = cons(print, c)
assert(is(c))
assert(car(c)==print)
assert(len(c)==2)

assert(is(cdr(c)))
assert(not null(cdr(c)))
assert(len(cdr(c))==1)
assert(car(cdr(c))=="new element")

a = cdr(cdr(c))
assert(type(a)=="table")
assert(is(a))
assert(null(a))
assert(equal(a, a))
assert(equal(a, new()))

ok = pcall(cdr, a)
assert(not ok)

-- 4
member, append, reverse, last = list.member, list.append, list.reverse, list.last

primes = new(2, 3, 5, 7)
assert(is(primes))
assert(not null(primes))
assert(car(primes)==2)
assert(member(2, primes))
assert(member(3, primes))
assert(member(5, primes))
assert(member(7, primes))
assert(not member(1, primes))
assert(not member({}, primes))
assert(not member(print, primes))

primes2 = append(primes, new())
assert(is(primes2))
assert(equal(primes, primes2))
assert(len(primes)==len(primes2))

primes2 = append(primes, new(11))
assert(is(primes2))
assert(not equal(primes, primes2))
assert((len(primes)+1) ==len(primes2))
assert(car(primes2)==2)
assert(member(2, primes2))
assert(member(3, primes2))
assert(member(5, primes2))
assert(member(7, primes2))
assert(member(11, primes2))
assert(not member(1, primes2))
assert(not member({}, primes2))
assert(not member(print, primes2))

primes2 = append(new(11), primes)
assert(is(primes2))
assert(not equal(primes, primes2))
assert((len(primes)+1) ==len(primes2))
assert(car(primes2)==11)
assert(member(2, primes2))
assert(member(3, primes2))
assert(member(5, primes2))
assert(member(7, primes2))
assert(member(11, primes2))
assert(not member(1, primes2))
assert(not member({}, primes2))
assert(not member(print, primes2))
assert(equal(primes, cdr(primes2)))

semirp = reverse(primes)
assert(is(semirp))
assert(not equal(primes, semirp))
assert(car(semirp)==7)
assert(member(2, semirp))
assert(member(3, semirp))
assert(member(5, semirp))
assert(member(7, semirp))
assert(not member(11, semirp))
assert(not member(1, semirp))
assert(not member({}, semirp))
assert(not member(print, semirp))

-- error "not a list"
assert(not (pcall(reverse, {})))
assert(not is({}))
assert(not (pcall(null, {})))
assert(not equal({}, new()))
assert(not equal({}, {}))

a = reverse(from({}))
assert(is(a))
assert(null(a))
assert(equal(a, a))
assert(equal(a, new()))

a = reverse(new())
assert(is(a))
assert(null(a))
assert(equal(a, a))
assert(equal(a, new()))

ok = pcall(last, a)
assert(not ok)

assert(last(primes)==7)
assert(last(reverse(primes))==2)
assert(last(from{"foo"})=="foo")


-- 2
andf, orf = list.andf, list.orf

assert(not andf())				    -- odd, but correct: same as andf(nil, nil)
assert(not andf(27))
assert(andf(1, 2))
assert(not andf(1, nil))
assert(not andf(true, false))
assert(not andf(nil, 1))
assert(not andf(false, true))

assert(not orf())				    -- odd, but correct: same as orf(nil, nil)
assert(orf(27))
assert(orf(1, 2))
assert(orf(1, nil))
assert(orf(true, false))
assert(orf(nil, 1))
assert(orf(false, true))
assert(not orf(false, false))


-- 3
flatten, reduce, filter = list.flatten, list.reduce, list.filter

a = flatten(new())
assert(type(a)=="table")
assert(is(a))
assert(null(a))
assert(equal(a, a))
assert(equal(a, new()))

a = flatten(new(new()))
assert(type(a)=="table")
assert(is(a))
assert(null(a))
assert(equal(a, a))
assert(equal(a, new()))

numnums = new(primes, new(primes), primes)
assert(is(numnums))
assert(not null(numnums))
assert(len(numnums)==3)
assert(equal(car(numnums), primes))
assert(equal(car(car(cdr(numnums))), primes))
assert(equal(last(numnums), primes))

nums = flatten(numnums)
assert(is(nums))
assert(not null(nums))
assert(len(nums)==(3 * len(primes)))
assert(not equal(car(nums), primes))
n = car(nums)
assert(n==2)

assert(reduce(andf, true, new(1, 2, 3, true, "hello", a, print)))
assert(not reduce(andf, true, new(1, 2, 3, true, nil, "hello", a, print)))
assert(not reduce(andf, true, new(1, 2, 3, true, false, "hello", a, print)))

plus = function(i, j) return i+j; end
assert(reduce(plus, 0, primes)==17)
assert(reduce(plus, 1000, primes2)==1028)

function even_p(i) return ((i//2)*2)==i; end
el = filter(even_p, primes)
assert(is(el))
assert(len(el)==1)
assert(car(el)==2)

el = filter(even_p, append(primes, primes))
assert(is(el))
assert(len(el)==2)
assert(car(el)==2)
assert(car(cdr(el))==2)

ll = filter(is, new(primes, primes))
assert(is(ll))
assert(len(ll)==2)
assert(equal(car(ll), primes))
assert(equal(car(cdr(ll)), primes))

ll = filter(is, primes)
assert(is(ll))
assert(null(ll))
assert(len(ll)==0)

ll = filter(is, {})
assert(is(ll))
assert(null(ll))
assert(len(ll)==0)

ll = filter(function(x) return true; end, {})
assert(is(ll))
assert(null(ll))
assert(len(ll)==0)


-- 3
apply, map, foreach = list.apply, list.map, list.foreach

p = apply(new, primes)
assert(is(p))
assert(equal(p, primes))

function sum(...) local s=0; for _,n in ipairs{...} do s=s+n; end; return s; end
assert(apply(sum, primes)==17)
assert(apply(sum, primes2)==28)
assert(apply(sum, {})==0)
assert(apply(sum, {99})==99)

function incr(i) return i+1; end
pplus = map(incr, primes)
assert(equal(pplus, new(3, 4, 6, 8)))
assert(null(map(incr, {})))

global = 0
function for_effect(i) global = global + 100; end
nothing = map(for_effect, primes)
assert(is(nothing))
assert(null(nothing))
assert(global==400)

global = 0
nothing = foreach(for_effect, append(primes, primes))
assert(nothing==nil)
assert(not is(nothing))
assert(global==800)


-- 1
ts = list.tostring

assert(not (pcall(ts, {})))			    -- not a list
assert(ts(from({}))=="{}")
assert(ts(new({})):sub(1,10)=="{table: 0x")
assert(ts(new(new()))=="{{}}")
assert(ts(primes)=="{2, 3, 5, 7}")
assert(ts(cons(true, primes))=="{true, 2, 3, 5, 7}")
assert(ts(new(print))=="{"..tostring(print).."}")


print("Done")
