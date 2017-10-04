# coding: utf-8
#  -*- Mode: Python; -*-                                              
# 
#  rosie.py     An interface to librosie
# 
#  © Copyright IBM Corporation 2016, 2017.
#  LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
#  AUTHOR: Jamie A. Jennings

# Development environment:
#   Mac OS X Sierra (10.12.6)
#   Python 2.7.10 (distributed with OS X)
#   cffi 1.9.1 (installed with: pip install cffi)

from cffi import FFI
import json, os, sys

ffi = FFI()
NULL = ffi.NULL

##
## N.B. We can't use ffi.string (because it uses NULL to mark the end of a string, like C does)
##

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

def to_cstr_ptr(py_string):
    return lib.rosie_new_string_ptr(py_string, len(py_string))

def from_cstr_ptr(cstr_ptr):
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
        Cresp = ffi.new("struct rosie_string *")
        ok = lib.rosie_config(self.engine, Cresp)
        if ok != 0:
            # TODO: Test call failure.
            # Want to show err msgs in the exception, but will this (below) work?
            raise RuntimeError("config() failed")
        resp = from_cstr_ptr(Cresp)
        lib.rosie_free_string(Cresp[0])
        return resp

    def compile(self, exp):
        Cerrs = ffi.new("struct rosie_string *")
        Cexp = lib.rosie_new_string_ptr(exp, len(exp))
        Cpat = ffi.new("int *")
        ok = lib.rosie_compile(self.engine, Cexp, Cpat, Cerrs)
        lib.rosie_free_string(Cexp[0])
        if ok != 0:
            # TODO: Test call failure.
            raise RuntimeError("compile() failed", from_cstr_ptr(errs))
        # TODO: create a python rplx object and define __del__ to call rosie_free_rplx()
        if Cpat[0] == 0:
            errs = from_cstr_ptr(Cerrs)
            lib.rosie_free_string(Cerrs[0])
        else:
            errs = None
        return Cpat, errs

    def load(self, src):
        Cerrs = ffi.new("struct rosie_string *")
        Csrc = to_cstr_ptr(src)
        Csuccess = ffi.new("int *")
        Cpkgname = ffi.new("struct rosie_string *")
        ok = lib.rosie_load(self.engine, Csuccess, Csrc, Cpkgname, Cerrs)
        if ok != 0:
            # TODO: Test call failure.
            raise RuntimeError("compile() failed", from_cstr_ptr(errs))
        errs = from_cstr_ptr(Cerrs)
        lib.rosie_free_string(Cerrs[0])
        return Csuccess[0], from_cstr_ptr(Cpkgname), errs

    def free_rplx(self, Cpat):
        lib.rosie_free_rplx(self.engine, Cpat[0])
        return None

## FUTURE:  Avoid using rosie_new_string_ptr / rosie_free_string_ptr.
## Maybe read the input data with f.readinto(buf), where buf is pre-allocated?
## Or is there a way to initialize a ffi.new("struct rosie_string *") using ffi.from_buffer()?

    def match(self, Cpat, input, start, encoder):
        match = ffi.new("struct rosie_matchresult *")
        Cinput = lib.rosie_new_string_ptr(input, len(input))
        ok = lib.rosie_match(self.engine, Cpat[0], start, encoder, Cinput, match)
        lib.rosie_free_string_ptr(Cinput)
        if ok != 0:
            # TODO: Test call failure.
            raise RuntimeError("match() failed with system error")
        left = match.leftover
        ttotal = match.ttotal
        tmatch = match.tmatch
        if match == ffi.NULL:
            raise ValueError("invalid compiled pattern (already freed?)")
        if match.data.ptr == ffi.NULL:
            return None, left, ttotal, tmatch
        data_buffer = ffi.buffer(match.data.ptr, match.data.len)
        return data_buffer, left, ttotal, tmatch

    def set_alloc_limit(self, newlimit):
        if (newlimit != 0) and (newlimit < 10):
            raise ValueError("new allocation limit must be 10 MB or higher (or zero for unlimited)")
        ok = lib.rosie_set_alloc_limit(self.engine, newlimit)
        if ok != 0:
            raise RuntimeError("set_alloc_limit() failed")

    def __del__(self):
        if self.engine != ffi.NULL:
            print "Garbage collecting engine", self
            lib.rosie_finalize(self.engine)



    
