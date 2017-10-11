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
#   cffi-1.11.1 pycparser-2.18 (installed with: pip install cffi)


from cffi import FFI
from ctypes.util import find_library
from os import path
import json

ffi = FFI()

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
     int abend;
     int ttotal;
     int tmatch;
} match;

str *rosie_new_string_ptr(byte_ptr msg, size_t len);
void rosie_free_string_ptr(str *s);
void rosie_free_string(str s);

void *rosie_new(str *errors);
void rosie_finalize(void *L);
int rosie_setlibpath_engine(void *L, char *newpath);
int rosie_set_alloc_limit(void *L, int newlimit);
int rosie_config(void *L, str *retvals);
int rosie_compile(void *L, str *expression, int *pat, str *errors);
int rosie_free_rplx(void *L, int pat);
int rosie_match(void *L, int pat, int start, char *encoder, str *input, match *match);
int rosie_trace(void *L, int pat, int start, char *trace_style, str *input, int *matched, str *trace);
int rosie_load(void *L, int *ok, str *src, str *pkgname, str *errors);
int rosie_import(void *L, int *ok, str *pkgname, str *as, str *errors);

""")

lib = None                # single instance of dynamic library
home = None               # path to ROSIE_HOME directory
libname = "librosie.so"

# -----------------------------------------------------------------------------
# ffi utilities

def new_rplx(engine):
    def free_rplx(obj):
        if obj[0] and engine.engine:
            lib.rosie_free_rplx(engine.engine, obj[0])
    obj = ffi.new("int *")
    return ffi.gc(obj, free_rplx)

def new_cstr(py_string=None):
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

# -----------------------------------------------------------------------------

# Problem: Can't make use of Rosie-level defaults because we create a new Rosie instance for every engine.
#
# Observation: The librosie implementation currently allows just one
#   ROSIE_HOME (globally).  This fixes the values of ROSIE_LIBDIR,
#   ROSIE_VERSION, and RPL_VERSION.  So the only default that can
#   matter on a per-engine basis is ROSIE_LIBPATH.
#
# Solution:
# - We could store that default here in Python, and set it each time we create a new engine.

# TODO:
# - Create a rosie class
# - Move config() to the rosie class
# - Define setlibpath for this class
# - When creating a new engine, set the engine's libpath (needed functionality) and the rosie
#   libpath (so that the config() method will show the right values).
#
# TO BE CONTINUED!

# def setlibpath(libpath):
#     ok = lib.rosie_setlibpath_default(lib, libpath)
#     if ok != 0:
#         raise RuntimeError("setpath() failed (please report this as a bug)")


# -----------------------------------------------------------------------------

class engine ():
    '''
    Create a Rosie pattern matching engine.  The first call to engine()
    will load librosie from one of the standard shared library
    directories for your system, or from a custom path provided as an
    argument.
    '''

    def __init__(self, custom_libpath=None):
        global lib, libname, home
        if not lib:
            if custom_libpath:
                libpath = path.join(custom_libpath, libname)
                if not path.isfile(libpath):
                    raise RuntimeError("Cannot find librosie at " + libpath)
            else:
                libpath = find_library(libname)
                if not libpath:
                    raise RuntimeError("Cannot find librosie using ctypes.util.find_library()")
            lib = ffi.dlopen(libpath)
        Cerrs = new_cstr()
        self.engine = lib.rosie_new(Cerrs)
        if self.engine == ffi.NULL:
            raise RuntimeError("librosie: " + read_cstr(Cerrs))
        return

    def config(self):
        Cresp = new_cstr()
        ok = lib.rosie_config(self.engine, Cresp)
        if ok != 0:
            raise RuntimeError("config() failed (please report this as a bug)")
        resp = read_cstr(Cresp)
        return resp

    def compile(self, exp):
        Cerrs = new_cstr()
        Cexp = new_cstr(exp)
        Cpat = new_rplx(self)
        ok = lib.rosie_compile(self.engine, Cexp, Cpat, Cerrs)
        if ok != 0:
            raise RuntimeError("compile() failed (please report this as a bug)")
        if Cpat[0] == 0:
            errs = read_cstr(Cerrs)
        else:
            errs = None
        return Cpat, errs

    def load(self, src):
        Cerrs = new_cstr()
        Csrc = new_cstr(src)
        Csuccess = ffi.new("int *")
        Cpkgname = new_cstr()
        ok = lib.rosie_load(self.engine, Csuccess, Csrc, Cpkgname, Cerrs)
        if ok != 0:
            raise RuntimeError("load() failed (please report this as a bug)")
        errs = read_cstr(Cerrs)
        pkgname = read_cstr(Cpkgname)
        return Csuccess[0], pkgname, errs

    def import_pkg(self, pkgname, as_name=None):
        Cerrs = new_cstr()
        Cas_name = new_cstr(as_name) if as_name else ffi.NULL
        Cpkgname = new_cstr(pkgname)
        Csuccess = ffi.new("int *")
        ok = lib.rosie_import(self.engine, Csuccess, Cpkgname, Cas_name, Cerrs)
        if ok != 0:
            raise RuntimeError("import() failed (please report this as a bug)")
        actual_pkgname = read_cstr(Cpkgname)
        errs = read_cstr(Cerrs)
        return Csuccess[0], actual_pkgname, errs

    def match(self, Cpat, input, start, encoder):
        if Cpat[0] == 0:
            raise ValueError("invalid compiled pattern")
        Cmatch = ffi.new("struct rosie_matchresult *")
        Cinput = new_cstr(input)
        ok = lib.rosie_match(self.engine, Cpat[0], start, encoder, Cinput, Cmatch)
        if ok != 0:
            raise RuntimeError("match() failed (please report this as a bug)")
        left = Cmatch.leftover
        abend = Cmatch.abend
        ttotal = Cmatch.ttotal
        tmatch = Cmatch.tmatch
        if Cmatch.data.ptr == ffi.NULL:
            if Cmatch.data.len == 0:
                return None, left, abend, ttotal, tmatch
            elif Cmatch.data.len == 1:
                raise ValueError("invalid compiled pattern (already freed?)")
        data_buffer = ffi.buffer(Cmatch.data.ptr, Cmatch.data.len)
        return data_buffer, left, abend, ttotal, tmatch

    def trace(self, Cpat, input, start, style):
        if Cpat[0] == 0:
            raise ValueError("invalid compiled pattern")
        Cmatched = ffi.new("int *")
        Cinput = new_cstr(input)
        Ctrace = new_cstr()
        ok = lib.rosie_trace(self.engine, Cpat[0], start, style, Cinput, Cmatched, Ctrace)
        if ok != 0:
            raise RuntimeError("trace() failed (please report this as a bug)")
        if Ctrace.ptr == ffi.NULL:
            if Ctrace.len == 2:
                return ValueError("invalid trace style")
            elif Ctrace.len == 1:
                raise ValueError("invalid compiled pattern (already freed?)")
        matched = False if Cmatched[0]==0 else True
        trace = read_cstr(Ctrace)
        return matched, trace

    def setlibpath(self, libpath):
        ok = lib.rosie_setlibpath_engine(self.engine, libpath)
        if ok != 0:
            raise RuntimeError("setpath() failed (please report this as a bug)")

    def set_alloc_limit(self, newlimit):
        if (newlimit != 0) and (newlimit < 10):
            raise ValueError("new allocation limit must be 10 MB or higher (or zero for unlimited)")
        ok = lib.rosie_set_alloc_limit(self.engine, newlimit)
        if ok != 0:
            raise RuntimeError("set_alloc_limit() failed (please report this as a bug)")

    def __del__(self):
        if hasattr(self, 'engine') and (self.engine != ffi.NULL):
            lib.rosie_finalize(self.engine)



    
