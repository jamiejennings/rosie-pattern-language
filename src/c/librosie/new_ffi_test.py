# MacOSX Python 2.7.10, cffi 1.7.0
#
# easy_install --user cffi
from cffi import FFI
import json

ffi = FFI()
ffi.cdef("""
int printf(const char *format, ...);   // copy-pasted from the man page
""")
C = ffi.dlopen(None)                     # loads the entire C namespace
arg = ffi.new("char[]", "world")         # equivalent to C code: char arg[] = "world";
C.printf("hi there, %s.\n", arg)         # call printf

ffi.cdef("""
struct string {
     uint32_t len;
     uint8_t *ptr;
};

struct string_array {
     uint32_t n;
     struct string **ptr;
};

struct string_array2 {
     uint32_t n;
     struct string *ptr;
};

void free_string(struct string foo);
uint32_t testbyvalue(struct string foo);
uint32_t testbyref(struct string *foo);
struct string testretstring(struct string *foo);
struct string_array testretarray(struct string foo);
struct string_array2 testretarray2(struct string foo);

/* extern int bootstrap (lua_State *L, const char *rosie_home); */
void require (const char *name, int assign_name);
void initialize(const char *rosie_home);
struct string rosie_api(const char *name, ...);
struct string new_engine(struct string *config);

""")


Rosie = ffi.dlopen("librosie.so")
Rosie.initialize("adjkasjdk")

null = ffi.new("char []", "null")
C.printf("null is set to this string: %s\n", null)
null_cstr_ptr = ffi.new("struct string *")
buf = bytearray()
buf.extend("null")
print(buf, len(buf))
null_cstr_ptr.len = len(buf)
null_cstr_ptr.ptr = ffi.from_buffer(buf)

foo = Rosie.new_engine(null_cstr_ptr)
print(foo)
retval = ffi.string(foo.ptr, foo.len)
print(retval)

retvals = json.loads(retval)
print(retvals)

eid = retvals[1]
print("eid = " + repr(eid) + ", len = " + str(len(eid)))

def to_cstr_ptr(py_string):
    cstr_ptr = ffi.new("struct string *")
    buf = bytearray(py_string, "utf8")
    cstr_ptr.len = len(buf)
    cstr_ptr.ptr = ffi.from_buffer(buf)
    return cstr_ptr

def from_cstr_ptr(cstr_ptr):
#    lst = ffi.unpack(cstr_ptr.ptr, cstr_ptr.len)
#    s = reduce(lambda s,i: s+chr(i), lst, '')
#    return s
    return ffi.buffer(cstr_ptr.ptr, cstr_ptr.len)[:]

print(from_cstr_ptr(to_cstr_ptr(eid)))

foo = Rosie.rosie_api("inspect_engine", to_cstr_ptr(eid), null_cstr_ptr)
tbl = json.loads(from_cstr_ptr(foo))
print("Return from inspect_engine is: code = " + str(tbl[0]) + ", tbl=" + str(tbl[1]))

print


## We can't use ffi.string (because it uses NULL as eos, like C)

eid_str = to_cstr_ptr(eid)
b = ffi.buffer(eid_str.ptr, eid_str.len)
print b[:], len(b)
print from_cstr_ptr(to_cstr_ptr(eid))

foobar = ffi.new("char []", "foobar")
ignored = ffi.new("struct string [1]", [[6, foobar]])
retarray = Rosie.testretarray(ignored[0])
print retarray.n
for i in range(0, retarray.n):
    print from_cstr_ptr(retarray.ptr[i])

    
