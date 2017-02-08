# coding: utf-8
#  -*- Mode: Python; -*-                                              
# 
#  rtest.py     A crude sample program in Python that uses librosie
# 
#  © Copyright IBM Corporation 2016.
#  LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
#  AUTHOR: Jamie A. Jennings

# Developed using MacOSX Python 2.7.10, cffi 1.7.0
# easy_install --user cffi

from cffi import FFI
import json, os, sys

ffi = FFI()

ROSIE_HOME = os.getenv("ROSIE_HOME")
if not ROSIE_HOME:
    print "Environment variable ROSIE_HOME not set.  (Must be set to the root of the rosie directory.)"
    sys.exit(-1)

# The C code below was taken from librosie.h (and librosie_gen.h)
ffi.cdef("""
typedef uint8_t * byte_ptr;

struct rosieL_string {
     uint32_t len;
     byte_ptr ptr;
};

struct rosieL_stringArray {
     uint32_t n;
     struct rosieL_string **ptr;
};

struct rosieL_string *rosieL_new_string(byte_ptr msg, size_t len);
struct rosieL_stringArray *rosieL_new_stringArray();
void rosieL_free_string(struct rosieL_string s);
void rosieL_free_string_ptr(struct rosieL_string *s);
void rosieL_free_stringArray(struct rosieL_stringArray r);
void rosieL_free_stringArray_ptr(struct rosieL_stringArray *r);

void *rosieL_initialize(struct rosieL_string *rosie_home, struct rosieL_stringArray *msgs);
void rosieL_finalize(void *L);

struct rosieL_stringArray rosieL_load_manifest(void *L, struct rosieL_string *manifest_file);
struct rosieL_stringArray rosieL_clear_environment(void *L, struct rosieL_string *optional_identifier);
struct rosieL_stringArray rosieL_load_string(void *L, struct rosieL_string *input);
struct rosieL_stringArray rosieL_set_match_exp_grep_TEMPORARY(void *L, struct rosieL_string *pattern_exp);
struct rosieL_stringArray rosieL_eval_file(void *L, struct rosieL_string *infilename, struct rosieL_string *outfilename, struct rosieL_string *errfilename, struct rosieL_string *wholefileflag);
struct rosieL_stringArray rosieL_inspect_engine(void *L);
struct rosieL_stringArray rosieL_load_file(void *L, struct rosieL_string *path);
struct rosieL_stringArray rosieL_configure_engine(void *L, struct rosieL_string *config_obj);
struct rosieL_stringArray rosieL_get_environment(void *L, struct rosieL_string *optional_identifier);
struct rosieL_stringArray rosieL_eval(void *L, struct rosieL_string *input_text, struct rosieL_string *start);
struct rosieL_stringArray rosieL_match(void *L, struct rosieL_string *input_text, struct rosieL_string *optional_start);
struct rosieL_stringArray rosieL_info(void *L);
struct rosieL_stringArray rosieL_match_file(void *L, struct rosieL_string *infilename, struct rosieL_string *outfilename, struct rosieL_string *errfilename, struct rosieL_string *wholefileflag);

""")

def to_cstr_ptr(py_string):
    return Rosie.rosieL_new_string(py_string, len(py_string))

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

Rosie = ffi.dlopen(ROSIE_HOME + "/ffi/librosie/librosie.so")

messages = Rosie.rosieL_new_stringArray()
engine = Rosie.rosieL_initialize(to_cstr_ptr(ROSIE_HOME), messages)
printArray(messages, "initialize")
Rosie.rosieL_free_stringArray_ptr(messages)

if engine == ffi.NULL:
    print "Error initializing librosie.  Exiting..."
    exit(-1)

config_raw = "{\"expression\": \"[:digit:]+\", \"encode\": \"json\"}"
config = to_cstr_ptr(config_raw)
print("config (as cstr pointer): " + from_cstr_ptr(config))

r = Rosie.rosieL_configure_engine(engine, config)
printArray(r, "configure_engine")
retvals = strings_from_array(r)
print retvals
Rosie.rosieL_free_stringArray(r)

r = Rosie.rosieL_inspect_engine(engine)
printArray(r, "inspect_engine")
retvals = strings_from_array(r)
Rosie.rosieL_free_stringArray(r)

tbl = json.loads(retvals[1])
print("Return from inspect_engine is: code = " + retvals[0] + ", tbl=" + str(tbl))

print

r = Rosie.rosieL_load_manifest(engine, to_cstr_ptr("$sys/MANIFEST"))
print(strings_from_array(r))
Rosie.rosieL_free_stringArray(r)

print

##
## N.B. We can't use ffi.string (because it uses NULL to mark the end of a string, like C does)
##

start = to_cstr_ptr("3")        # 1-based indexing, so this starts matching at 3rd character

foo = "1239999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999";
foo_string = to_cstr_ptr(foo);
r = Rosie.rosieL_match(engine, foo_string, start); 
printArray(r, "match");
Rosie.rosieL_free_stringArray(r)
        
foo = "1230000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";
foo_string = to_cstr_ptr(foo);
r = Rosie.rosieL_match(engine, foo_string, ffi.NULL); # 'None' does not work here
printArray(r, "match");
Rosie.rosieL_free_stringArray(r)

config = to_cstr_ptr("{\"expression\": \"(basic.network_patterns)+\"}")
r = Rosie.rosieL_configure_engine(engine, config)
printArray(r, "configure_engine")
Rosie.rosieL_free_stringArray(r)

input_string = to_cstr_ptr("10.0.0.1 www.ibm.com foobar@example.com") 
r = Rosie.rosieL_match(engine, input_string, ffi.NULL)  # 'None' does not work here
printArray(r, "match")
Rosie.rosieL_free_stringArray(r)



Rosie.rosieL_finalize(engine)

