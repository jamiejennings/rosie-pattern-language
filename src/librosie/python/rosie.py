# coding: utf-8
#  -*- Mode: Python; -*-                                              
# 
#  rosie.py     An interface to librosie from Python
# 
#  © Copyright IBM Corporation 2016, 2017.
#  LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
#  AUTHOR: Jamie A. Jennings

# N.B. A Rosie installation requires librosie.so AND a set of files
# under the directory name 'rosie'.  For example, when Rosie is
# installed in /usr/local, we expect to find these files:
#
#   /usr/local/lib/librosie.so
#   /usr/local/lib/rosie             (directory)

# Development environment:
#   Mac OS X Sierra (10.12.6)
#   Python 2.7.10 (distributed with OS X)
#   cffi-1.11.1 pycparser-2.18 (installed with: pip install cffi)

from cffi import FFI
import os
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

str *rosie_string_ptr_from(byte_ptr msg, size_t len);
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
int rosie_matchfile(void *L, int pat, char *encoder, int wholefileflag,
		    char *infilename, char *outfilename, char *errfilename,
		    int *cin, int *cout, int *cerr,
		    str *err);
int rosie_trace(void *L, int pat, int start, char *trace_style, str *input, int *matched, str *trace);
int rosie_load(void *L, int *ok, str *src, str *pkgname, str *errors);
int rosie_loadfile(void *e, int *ok, str *fn, str *pkgname, str *errors);
int rosie_import(void *e, int *ok, str *pkgname, str *as, str *actual_pkgname, str *messages);

void free(void *obj);

""")

lib = None                # single instance of dynamic library

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
        obj = lib.rosie_string_ptr_from(py_string, len(py_string))
        return ffi.gc(obj, lib.free)
    else:
        obj = ffi.new("struct rosie_string *")
        return ffi.gc(obj, free_cstr_ptr)

def read_cstr(cstr_ptr):
    if cstr_ptr.ptr == ffi.NULL:
        return None
    else:
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
# TO BE CONTINUED.


# -----------------------------------------------------------------------------

class engine ():
    '''
    Create a Rosie pattern matching engine.  The first call to engine()
    will load librosie from one of the standard shared library
    directories for your system, or from a custom path provided as an
    argument.
    '''

    def __init__(self, custom_libpath=None):
        global lib
        ostype = os.uname()[0]
        if ostype=="Darwin":
            libname = "librosie.dylib"
        else:
            libname = "librosie.so"
        if not lib:
            if custom_libpath:
               libpath = os.path.join(custom_libpath, libname)
               if not os.path.isfile(libpath):
                   raise RuntimeError("Cannot find librosie at " + libpath)
            else:
                libpath = libname
            lib = ffi.dlopen(libpath, ffi.RTLD_GLOBAL)
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
            Cpat = None
        return Cpat, read_cstr(Cerrs)

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

    def loadfile(self, fn):
        Cerrs = new_cstr()
        Cfn = new_cstr(fn)
        Csuccess = ffi.new("int *")
        Cpkgname = new_cstr()
        ok = lib.rosie_loadfile(self.engine, Csuccess, Cfn, Cpkgname, Cerrs)
        if ok != 0:
            raise RuntimeError("loadfile() failed (please report this as a bug)")
        errs = read_cstr(Cerrs)
        pkgname = read_cstr(Cpkgname)
        return Csuccess[0], pkgname, errs

    def import_pkg(self, pkgname, as_name=None):
        Cerrs = new_cstr()
        Cas_name = new_cstr(as_name) if as_name else ffi.NULL
        Cpkgname = new_cstr(pkgname)
        Cactual_pkgname = new_cstr()
        Csuccess = ffi.new("int *")
        ok = lib.rosie_import(self.engine, Csuccess, Cpkgname, Cas_name, Cactual_pkgname, Cerrs)
        if ok != 0:
            raise RuntimeError("import() failed (please report this as a bug)")
        actual_pkgname = read_cstr(Cactual_pkgname) #if Cactual_pkgname.ptr != ffi.NULL else None
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

    def matchfile(self, Cpat, encoder,
                  infile=None,  # stdin
                  outfile=None, # stdout
                  errfile=None, # stderr
                  wholefile=False):
        if Cpat[0] == 0:
            raise ValueError("invalid compiled pattern")
        Ccin = ffi.new("int *")
        Ccout = ffi.new("int *")
        Ccerr = ffi.new("int *")
        wff = 1 if wholefile else 0
        Cerrmsg = new_cstr()
        ok = lib.rosie_matchfile(self.engine, Cpat[0], encoder, wff,
                                 infile or "", outfile or "", errfile or "",
                                 Ccin, Ccout, Ccerr, Cerrmsg)
        if ok != 0:
            raise RuntimeError("matchfile() failed: " + read_cstr(Cerrmsg))

        if Ccin[0] == -1:       # Error occurred
            if Ccout[0] == 1:
                raise ValueError("invalid compiled pattern (already freed?)")
            elif Ccout[0] == 2:
                raise ValueError("invalid encoder")
            elif Ccout[0] == 3:
                raise ValueError(read_cstr(Cerrmsg)) # file i/o error
            else:
                raise ValueError("unknown error caused matchfile to fail")
        return Ccin[0], Ccout[0], Ccerr[0]

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



    
