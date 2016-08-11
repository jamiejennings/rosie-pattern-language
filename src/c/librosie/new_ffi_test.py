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

struct string *new_string(char *msg, size_t len);
struct stringArray *new_stringArray();
struct string *copy_string_ptr(struct string *src);
void free_string(struct string foo);
void free_string_ptr(struct string *foo);
void free_stringArray(struct stringArray r);
void free_stringArray_ptr(struct stringArray *r);

void *initialize(const char *rosie_home, struct stringArray *msgs);
void finalize(void *L);
struct stringArray rosie_api(void *L, const char *name, ...);
struct stringArray inspect_engine(void *L);
struct stringArray configure_engine(void *L, struct string *config);
struct stringArray match(void *L, struct string *input);

""")

def to_cstr_ptr(py_string):
    return Rosie.new_string(py_string, len(py_string))

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

Rosie = ffi.dlopen("librosie.so")

messages = Rosie.new_stringArray()
engine = Rosie.initialize("/Users/jjennings/Work/Dev/rosie-pattern-language", messages)
printArray(messages, "initialize")
Rosie.free_stringArray_ptr(messages)

config_raw = "{\"expression\": \"[:digit:]+\", \"encode\": \"json\"}"
config = to_cstr_ptr(config_raw)
print("config (as cstr pointer): " + from_cstr_ptr(config))

r = Rosie.configure_engine(engine, config)
printArray(r, "configure_engine")
retvals = strings_from_array(r)
print retvals
Rosie.free_stringArray(r)

r = Rosie.inspect_engine(engine)
printArray(r, "inspect_engine")
retvals = strings_from_array(r)
Rosie.free_stringArray(r)

tbl = json.loads(retvals[1])
print("Return from inspect_engine is: code = " + retvals[0] + ", tbl=" + str(tbl))

print

##
## N.B. We can't use ffi.string (because it uses NULL as eos, like C)
##

# Loop prep

foo2 = "1230000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";
foo_string2 = to_cstr_ptr(foo2);

r = Rosie.match(engine, foo_string2); 
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
        retval = Rosie.match(engine, foo_string)
    else:
        retval = saved
    strings = strings_from_array(retval)
    code = strings[0]
    if code != "true":
        print "Error code returned from match api"
    json_string = strings[1]
    if call_rosie:
        Rosie.free_stringArray(retval)
    if M==1:
        if code=="true":
            print "Successful call to match\n"
        else:
            print "Call to match FAILED\n"
            print json_string, "\n"

    obj_to_return_to_caller = json.loads(json_string)
    # print obj_to_return_to_caller

print " done.\n"
Rosie.finalize(engine)

