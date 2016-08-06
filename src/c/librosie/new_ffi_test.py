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

struct stringArray {
     uint32_t n;
     struct string **ptr;
};

struct string *heap_allocate_stringN(const char *msg, size_t len);
struct string *copy_string_ptr(struct string *src);
void free_string(struct string foo);
void free_string_ptr(struct string *foo);
void free_stringArray(struct stringArray r);

int initialize(const char *rosie_home);
void finalize();
struct stringArray rosie_api(const char *name, ...);
struct stringArray new_engine(struct string *config);
struct stringArray inspect_engine(struct string *eid_string);
struct stringArray match(struct string *eid_string, struct string *input);
void delete_engine(struct string *eid_string);

""")

Rosie = ffi.dlopen("librosie.so")
Rosie.initialize("/Users/jjennings/Work/Dev/rosie-pattern-language")

null = ffi.new("char []", "null")
C.printf("null is set to this string: %s\n", null)
null_cstr_ptr = ffi.new("struct string *")
buf = bytearray()
buf.extend("null")
print(buf, len(buf))
null_cstr_ptr.len = len(buf)
null_cstr_ptr.ptr = ffi.from_buffer(buf)

def to_cstr_ptr(py_string):
    # cstr_ptr = ffi.new("struct string *")
    # cstr_ptr.ptr = ffi.new("char []", py_string)
    # cstr_ptr.len = len(py_string)
    # copy = Rosie.copy_string_ptr(cstr_ptr)
    # return copy
    return Rosie.heap_allocate_stringN(py_string, len(py_string))

def from_cstr_ptr(cstr_ptr):
    return ffi.buffer(cstr_ptr.ptr, cstr_ptr.len)[:]

def strings_from_array(a):
    lst = []
    for i in range(0, a.n):
        lst.append(from_cstr_ptr(a.ptr[i]))
    return lst

def printArray(a, caller_name):
    print "Values returned from", caller_name
    print " ", a.n, "values:"
    lst = strings_from_array(a)
    for i in range(len(lst)):
        print " [", i, "] len =", a.ptr[i].len, " and  ptr =", lst[i]
    return

config_raw = "{\"expression\": \"[:digit:]+\", \"encode\": \"json\"}"
config = to_cstr_ptr(config_raw)
print("config (as cstr pointer): " + from_cstr_ptr(config))

r = Rosie.new_engine(config)
printArray(r, "new_engine")
retvals = strings_from_array(r)
print retvals

eid = retvals[1]
print("eid = " + repr(eid) + ", len = " + str(len(eid)))

eid_string = to_cstr_ptr(eid)
print "Ensuring that we can go from cstr to python string and back:", from_cstr_ptr(eid_string)

r = Rosie.rosie_api("inspect_engine", eid_string, null_cstr_ptr)
printArray(r, "inspect_engine")
retvals = strings_from_array(r)

tbl = json.loads(retvals[1])
print("Return from inspect_engine is: code = " + retvals[0] + ", tbl=" + str(tbl))

print

##
## N.B. We can't use ffi.string (because it uses NULL as eos, like C)
##

# Loop prep

eid_string = to_cstr_ptr(eid)
print eid_string.len, from_cstr_ptr(eid_string)

foo2 = "1230000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";
foo_string2 = to_cstr_ptr(foo2);

r = Rosie.match(eid_string, foo_string2); 
printArray(r, "match");
saved = r;

# Loop     

M = 1000000
#M = 1
call_rosie = True

foo = "1239999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999";
foo_string = to_cstr_ptr(foo);

print "Looping..."
for i in range(0,5*M):
    if call_rosie:
        retval = Rosie.match(eid_string, foo_string)
    else:
        retval = saved
    strings = strings_from_array(retval)
    code = strings[0]
    if code != "true":
        print "Error code returned from match api"
    json_string = strings[1]
    if call_rosie:
        Rosie.free_stringArray(retval)
    # if code=="true":
    #     print "Successful call to match\n"
    # else:
    #     print "Call to match FAILED\n"
    # print json_string, "\n"

    obj_to_return_to_caller = json.loads(json_string)
    # print obj_to_return_to_caller

print " done.\n"
    

Rosie.delete_engine(to_cstr_ptr(eid))
Rosie.finalize()

