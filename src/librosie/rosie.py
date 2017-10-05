# coding: utf-8
#  -*- Mode: Python; -*-                                              
# 
#  rosie.py     An interface to librosie from Python
# 
#  © Copyright IBM Corporation 2016, 2017.
#  LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
#  AUTHOR: Jamie A. Jennings

# Development environment:
#   Mac OS X Sierra (10.12.6)
#   Python 2.7.10 (distributed with OS X)
#   cffi 1.9.1 (installed with: pip install cffi)

from cffi import FFI
import json

ffi = FFI()
NULL = ffi.NULL

## N.B. We can't use ffi.string (because it uses NULL to mark the end of a string, like C does)

# See librosie.h
ffi.cdef("""

typedef uint8_t * byte_ptr;

typedef struct rosie_string {
     uint32_t len;
     byte_ptr ptr;
} str;

typedef struct rosie_matchresult {
     str data;
     int leftover;
     int ttotal;
     int tmatch;
} match;

str *rosie_new_string_ptr(byte_ptr msg, size_t len);
void rosie_free_string_ptr(str *s);
void rosie_free_string(str s);

void *rosie_new();
void rosie_finalize(void *L);
int rosie_set_alloc_limit(void *L, int newlimit);
int rosie_config(void *L, str *retvals);
int rosie_compile(void *L, str *expression, int *pat, str *errors);
int rosie_free_rplx(void *L, int pat);
int rosie_match(void *L, int pat, int start, char *encoder, str *input, match *match);
int rosie_load(void *L, int *ok, str *src, str *pkgname, str *errors);

""")

lib = None                # single instance of dynamic library
home = None               # path to ROSIE_HOME directory

def cstr(py_string=None):
    def free_cstr_ptr(local_cstr_obj):
        lib.rosie_free_string(local_cstr_obj[0])
    if py_string:
        obj = lib.rosie_new_string_ptr(py_string, len(py_string))
        return ffi.gc(obj, lib.rosie_free_string_ptr)
    else:
        obj = ffi.new("struct rosie_string *")
        return ffi.gc(obj, free_cstr_ptr)

def read_cstr(cstr_ptr):
    return ffi.buffer(cstr_ptr.ptr, cstr_ptr.len)[:]

# FUTURE: Support an optional argument for the engine name (helps when debugging)
class engine ():
    'put docstring here'

    def __init__(self, librosie_path):
        global lib, home
        if not lib:
            lib = ffi.dlopen(librosie_path)
            # TODO: Throw exception if ffi cannot open the dynamic library

        self.engine = lib.rosie_new()
        if self.engine == ffi.NULL:
            raise RuntimeError("Error initializing librosie.  Exiting...")
        return

    def config(self):
        Cresp = cstr()#_ptr()
        ok = lib.rosie_config(self.engine, Cresp)
        if ok != 0:
            # TODO: Test call failure.
            # Want to show err msgs in the exception, but will this (below) work?
            raise RuntimeError("config() failed")
        resp = read_cstr(Cresp)
#        free_cstr_ptr(Cresp)
        return resp

    def compile(self, exp):
        Cerrs = cstr()#_ptr()
        Cexp = cstr(exp)
        Cpat = ffi.new("int *")
        ok = lib.rosie_compile(self.engine, Cexp, Cpat, Cerrs)
#        free_cstr(Cexp)
        if ok != 0:
            # TODO: Test call failure.
            raise RuntimeError("compile() failed", read_cstr(errs))
        # TODO: create a python rplx object and define __del__ to call rosie_free_rplx()
        if Cpat[0] == 0:
            errs = read_cstr(Cerrs)
#            free_cstr_ptr(Cerrs)
        else:
            errs = None
        return Cpat, errs

    def load(self, src):
        Cerrs = cstr()#_ptr()
        Csrc = cstr(src)
        Csuccess = ffi.new("int *")
        Cpkgname = cstr()#_ptr()
        ok = lib.rosie_load(self.engine, Csuccess, Csrc, Cpkgname, Cerrs)
        if ok != 0:
            # TODO: Test call failure.
            raise RuntimeError("compile() failed", read_cstr(errs))
        errs = read_cstr(Cerrs)
#        free_cstr_ptr(Cerrs)
        pkgname = read_cstr(Cpkgname)
#        free_cstr_ptr(Cpkgname)
        return Csuccess[0], pkgname, errs

    def free_rplx(self, Cpat):
        lib.rosie_free_rplx(self.engine, Cpat[0])

    def match(self, Cpat, input, start, encoder):
        Cmatch = ffi.new("struct rosie_matchresult *")
        Cinput = cstr(input)
        ok = lib.rosie_match(self.engine, Cpat[0], start, encoder, Cinput, Cmatch)
#        free_cstr(Cinput)
        if ok != 0:
            raise RuntimeError("match() failed with an internal error (please report this as a bug)")
        if Cmatch == ffi.NULL:
            raise ValueError("invalid compiled pattern (already freed?)")
        left = Cmatch.leftover
        ttotal = Cmatch.ttotal
        tmatch = Cmatch.tmatch
        if Cmatch.data.ptr == ffi.NULL:
            return None, left, ttotal, tmatch
        data_buffer = ffi.buffer(Cmatch.data.ptr, Cmatch.data.len)
        return data_buffer, left, ttotal, tmatch

    def set_alloc_limit(self, newlimit):
        if (newlimit != 0) and (newlimit < 10):
            raise ValueError("new allocation limit must be 10 MB or higher (or zero for unlimited)")
        ok = lib.rosie_set_alloc_limit(self.engine, newlimit)
        if ok != 0:
            raise RuntimeError("set_alloc_limit() failed with an internal error (please report this as a bug)")

    def __del__(self):
        if self.engine != ffi.NULL:
            lib.rosie_finalize(self.engine)



    
