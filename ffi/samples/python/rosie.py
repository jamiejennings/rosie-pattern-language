# coding: utf-8
#  -*- Mode: Python; -*-                                              
# 
#  rosie.py     An interface to librosie
# 
#  © Copyright IBM Corporation 2016, 2017.
#  LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
#  AUTHOR: Jamie A. Jennings

# Developed using MacOSX Python 2.7.10, cffi 1.7.0
# easy_install --user cffi

from cffi import FFI
import json, os, sys

ffi = FFI()
NULL = ffi.NULL

##
## N.B. We can't use ffi.string (because it uses NULL to mark the end of a string, like C does)
##

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

def to_cstr_ptr(Rosie, py_string):
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


'''
rosie                # global, single instance of dynamic library
rosie_home           # path to ROSIE_HOME directory

'''
    
class initialize():
    'put docstring here'

    rosie_home = None
    rosie_instance = None
    
    # TODO: add an optional rosie_home arg
    def __init__(self):

        if not self.rosie_home:
            self.rosie_home = os.getenv("ROSIE_HOME")
        if not self.rosie_home:
            raise ValueError("Environment variable ROSIE_HOME not set.  (Must be set to the root of the rosie directory.)")
        # TODO: Catch an exception here, if ffi cannot open the dynamic library
        self.rosie_instance = ffi.dlopen(self.rosie_home + "/ffi/librosie/librosie.so")

    def engine(self):
        return engine(self)
    
    def get_retvals(self, messages):
        return self._get_retvals(messages, self.rosie_instance.rosieL_free_stringArray)
    
    def get_retvals_from_ptr(self, messages):
        return self._get_retvals(messages, self.rosie_instance.rosieL_free_stringArray_ptr)

    def _get_retvals(self, messages, free):
        retvals = strings_from_array(messages)
        assert retvals
        free(messages) #self.rosie_instance.rosie.rosieL_free_stringArray(messages)
        code = retvals[0]
        if code != 'true':
            raise ValueError(retvals[1])
        return retvals[1:]

# TODO: Support an optional argument for the engine name (helps when debugging)
class engine ():
    'put docstring here'

    def __init__(self, rosie_instance):
        # if not rosie:
        #     raise #"Exception indicating that rosie was not initialized"
        # if not rosie_home:
        #     raise #"Exception indicating that rosie_home is not set"

        self.name = "anonymous"
        self.rosie = rosie_instance
        messages = self.rosie.rosie_instance.rosieL_new_stringArray()
        self.engine = self.rosie.rosie_instance.rosieL_initialize(to_cstr_ptr(self.rosie.rosie_instance, self.rosie.rosie_home), messages)
        #printArray(messages, "initialize")
        retvals = self.rosie.get_retvals_from_ptr(messages)
        self.id = retvals[0]
        if self.engine == ffi.NULL:
            raise #"Error initializing librosie.  Exiting..."
        return

    def configure(self, config_string):
        config = to_cstr_ptr(self.rosie.rosie_instance, config_string)
        r = self.rosie.rosie_instance.rosieL_configure_engine(self.engine, config)
        #printArray(r, "configure_engine")
        retvals = self.rosie.get_retvals(r)
        return retvals

    def inspect(self):
        r = self.rosie.rosie_instance.rosieL_inspect_engine(self.engine)
        #printArray(r, "inspect_engine")
        retvals = self.rosie.get_retvals(r)
        return retvals

    def load_manifest(self, path):
        r = self.rosie.rosie_instance.rosieL_load_manifest(self.engine, to_cstr_ptr(self.rosie.rosie_instance, path))
        #printArray(r, "load_manifest")
        retvals = self.rosie.get_retvals(r)
        return retvals

    def load_file(self, path):
        r = self.rosie.rosie_instance.rosieL_load_file(self.engine, to_cstr_ptr(self.rosie.rosie_instance, path))
        retvals = self.rosie.get_retvals(r)
        return retvals

    def match(self, input_py_string, start):
        return self._match_or_eval(input_py_string, start, self.rosie.rosie_instance.rosieL_match)

    def eval(self, input_py_string, start):
        return self._match_or_eval(input_py_string, start, self.rosie.rosie_instance.rosieL_eval)

    def _match_or_eval(self, input_py_string, start, operation):
        # TODO: use varargs so that the start argument may be omitted
        if start is None: start = 1 # Rosie uses Lua's 1-based indexing
        input_string = to_cstr_ptr(self.rosie.rosie_instance, input_py_string)
        start_as_string = to_cstr_ptr(self.rosie.rosie_instance, str(start))
        r = operation(self.engine, input_string, start_as_string); 
        retvals = self.rosie.get_retvals(r)
        return retvals

    def __del__(self):
        print "Garbage collecting engine", self.id
        self.rosie.rosie_instance.rosieL_finalize(self.engine)


    
