# coding: utf-8
#  -*- Mode: Python; -*-                                              
# 
#  rosie.py     An interface to librosie from Python 2.7 and 3.6
# 
#  © Copyright IBM Corporation 2016, 2017, 2018.
#  LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
#  AUTHOR: Jamie A. Jennings

# Development environment:
#   Mac OS X Sierra (10.13.3)
#   Python 2.7.10 (distributed with OS X)
#   Python 3.6.5 (installed via brew on OS X)
#   cffi-1.11.4

# TODO:
# - replace magic error code numbers with constants

from __future__ import unicode_literals

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
int rosie_libpath(void *L, str *newpath);
int rosie_alloc_limit(void *L, int *newlimit, int *usage);
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
int rosie_read_rcfile(void *e, str *filename, int *file_exists, str *options, str *messages);
int rosie_execute_rcfile(void *e, str *filename, int *file_exists, int *no_errors, str *messages);

int rosie_expression_refs(void *e, str *input, str *refs, str *messages);
int rosie_block_refs(void *e, str *input, str *refs, str *messages);
int rosie_expression_deps(void *e, str *input, str *deps, str *messages);
int rosie_block_deps(void *e, str *input, str *deps, str *messages);
int rosie_parse_expression(void *e, str *input, str *parsetree, str *messages);
int rosie_parse_block(void *e, str *input, str *parsetree, str *messages);

void free(void *obj);

""")

# Single instance of dynamic library
_lib = None

# Values of _librosie_path:
#
#   librosie_system --> Search for librosie in system-dependent directories,
#       (e.g. /usr/local/lib), which can be affected LD_LIBRARY_PATH and related
#       environment variables. 
#
#   librosie_local --> Load librosie from the same directory as this file,
#       rosie.py.  Equivalent to using '//' as the argument.
#
#   path (string) --> Load librosie from the given path.  If the path
#       starts with '//' it is interpreted as relative to where this
#       file is installed.  A path starting with './' is relative to
#       the current directory of the process, and is discouraged.
#
#   None --> First try librosie_local, and if that fails, try librosie_system.

_librosie_path = None       
class _librosie_config():
    def __init__(self, name):
        self.name = name
    def __str__(self):
        return name
librosie_system = _librosie_config('*system*')
librosie_local = _librosie_config('*local*')

_librosie_name = None

# -----------------------------------------------------------------------------
# ffi utilities

def free_cstr_ptr(local_cstr_obj):
    _lib.rosie_free_string(local_cstr_obj[0])

# Note: bstring will be gc'd at the end of new_cstr unless we return
# it AND it is bound to a variable by the caller.  This is ugly, but
# seems necessary for Python3.  There must be a better way to cope
# with the fact that Python3 has separate, incompatible types for
# unicode strings (str) and byte arrays (bytes).
def _new_cstr(bstring=None):
    if bstring:
        obj = _lib.rosie_string_ptr_from(bstring, len(bstring))
        return ffi.gc(obj, _lib.free)
    elif bstring is None:
        obj = ffi.new("struct rosie_string *")
        return ffi.gc(obj, free_cstr_ptr)
    else:
        raise ValueError("Unsupported argument type: " + str(type(pystring)))

def _read_cstr(cstr_ptr):
    if cstr_ptr.ptr == ffi.NULL:
        return None
    else:
        return bytes(ffi.buffer(cstr_ptr.ptr, cstr_ptr.len)[:])

# -----------------------------------------------------------------------------

def load(path = None, **kwargs):
    global _lib, _librosie_path
    quiet = False
    if 'quiet' in kwargs:
        if kwargs['quiet']:
            quiet = True
    if _lib:
        if quiet: return
        else: raise RuntimeError('librosie has already been loaded from ' + _librosie_path)
    if path == None:
        try:
            _load_from('//')   # local
        except RuntimeError:
            try:
                _load_from('')     # system
            except RuntimeError:
                raise RuntimeError('Cannot find librosie in local or system locations')
    elif path == librosie_system:
        _load_from('')
    elif path == librosie_local:
        _load_from('//')
    else:
        _load_from(path)
    return

def _load_from(path_string):
    global _librosie_name, _librosie_path, _lib
    if not _librosie_name:
        ostype = os.uname()[0]
        if ostype=="Darwin":
            _librosie_name = "librosie.dylib"
        else:
            _librosie_name = "librosie.so"
    if path_string[0:2]=='//':
        libpath = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                               path_string[2:],
                               _librosie_name)
    else:
        libpath = os.path.join(path_string, _librosie_name)
    _lib = ffi.dlopen(libpath, ffi.RTLD_LAZY | ffi.RTLD_GLOBAL)
    _librosie_path = libpath

def librosie_path():
    return _librosie_path

class engine ():
    '''
    A Rosie pattern matching engine is used to load/import RPL code
    (patterns) and to do matching.  Create as many engines as you need.
    '''
    def __init__(self):
        global _lib
        if not _lib: load()
        Cerrs = _new_cstr()
        self.engine = _lib.rosie_new(Cerrs)
        if self.engine == ffi.NULL:
            raise RuntimeError("librosie: " + str(_read_cstr(Cerrs)))
        return
    
    def config(self):
        Cresp = _new_cstr()
        ok = _lib.rosie_config(self.engine, Cresp)
        if ok != 0:
            raise RuntimeError("config() failed (please report this as a bug)")
        resp = _read_cstr(Cresp)
        return resp

    def compile(self, exp):
        Cerrs = _new_cstr()
        Cexp = _new_cstr(exp)
        pat = rplx(self)
        ok = _lib.rosie_compile(self.engine, Cexp, pat.id, Cerrs)
        if ok != 0:
            raise RuntimeError("compile() failed (please report this as a bug)")
        if pat.id[0] == 0:
            pat = None
        return pat, _read_cstr(Cerrs)

    def load(self, src):
        Cerrs = _new_cstr()
        Csrc = _new_cstr(src)
        Csuccess = ffi.new("int *")
        Cpkgname = _new_cstr()
        ok = _lib.rosie_load(self.engine, Csuccess, Csrc, Cpkgname, Cerrs)
        if ok != 0:
            raise RuntimeError("load() failed (please report this as a bug)")
        errs = _read_cstr(Cerrs)
        pkgname = _read_cstr(Cpkgname)
        return Csuccess[0], pkgname, errs

    def loadfile(self, fn):
        Cerrs = _new_cstr()
        Cfn = _new_cstr(fn)
        Csuccess = ffi.new("int *")
        Cpkgname = _new_cstr()
        ok = _lib.rosie_loadfile(self.engine, Csuccess, Cfn, Cpkgname, Cerrs)
        if ok != 0:
            raise RuntimeError("loadfile() failed (please report this as a bug)")
        errs = _read_cstr(Cerrs)
        pkgname = _read_cstr(Cpkgname)
        return Csuccess[0], pkgname, errs

    def import_pkg(self, pkgname, as_name=None):
        Cerrs = _new_cstr()
        if as_name:
            Cas_name = _new_cstr(as_name)
        else:
            Cas_name = ffi.NULL
        Cpkgname = _new_cstr(pkgname)
        Cactual_pkgname = _new_cstr()
        Csuccess = ffi.new("int *")
        ok = _lib.rosie_import(self.engine, Csuccess, Cpkgname, Cas_name, Cactual_pkgname, Cerrs)
        if ok != 0:
            raise RuntimeError("import() failed (please report this as a bug)")
        actual_pkgname = _read_cstr(Cactual_pkgname) #if Cactual_pkgname.ptr != ffi.NULL else None
        errs = _read_cstr(Cerrs)
        return Csuccess[0], actual_pkgname, errs

    def match(self, pat, input, start, encoder):
        if (pat is None) or (pat.id[0] == 0):
            raise ValueError("invalid compiled pattern")
        Cmatch = ffi.new("struct rosie_matchresult *")
        Cinput = _new_cstr(input)
        ok = _lib.rosie_match(self.engine, pat.id[0], start, encoder, Cinput, Cmatch)
        if ok != 0:
            raise RuntimeError("match() failed (please report this as a bug)")
        left = Cmatch.leftover
        abend = Cmatch.abend
        ttotal = Cmatch.ttotal
        tmatch = Cmatch.tmatch
        if Cmatch.data.ptr == ffi.NULL:
            if Cmatch.data.len == 0:
                return False, left, abend, ttotal, tmatch
            elif Cmatch.data.len == 1:
                return True, left, abend, ttotal, tmatch
            elif Cmatch.data.len == 2:
                raise ValueError("invalid output encoder")
            elif Cmatch.data.len == 4:
                raise ValueError("invalid compiled pattern (already freed?)")
        data = _read_cstr(Cmatch.data)
        return data, left, abend, ttotal, tmatch

    def trace(self, pat, input, start, style):
        if pat.id[0] == 0:
            raise ValueError("invalid compiled pattern")
        Cmatched = ffi.new("int *")
        Cinput = _new_cstr(input)
        Ctrace = _new_cstr()
        ok = _lib.rosie_trace(self.engine, pat.id[0], start, style, Cinput, Cmatched, Ctrace)
        if ok != 0:
            raise RuntimeError("trace() failed (please report this as a bug)")
        if Ctrace.ptr == ffi.NULL:
            if Ctrace.len == 2:
                raise ValueError("invalid trace style")
            elif Ctrace.len == 1:
                raise ValueError("invalid compiled pattern (already freed?)")
        matched = False if Cmatched[0]==0 else True
        trace = _read_cstr(Ctrace)
        return matched, trace

    def matchfile(self, pat, encoder,
                  infile=None,  # stdin
                  outfile=None, # stdout
                  errfile=None, # stderr
                  wholefile=False):
        if pat.id[0] == 0:
            raise ValueError("invalid compiled pattern")
        Ccin = ffi.new("int *")
        Ccout = ffi.new("int *")
        Ccerr = ffi.new("int *")
        wff = 1 if wholefile else 0
        Cerrmsg = _new_cstr()
        ok = _lib.rosie_matchfile(self.engine,
                                 pat.id[0],
                                 encoder,
                                 wff,
                                 infile or b"",
                                 outfile or b"",
                                 errfile or b"",
                                 Ccin, Ccout, Ccerr, Cerrmsg)
        if ok != 0:
            raise RuntimeError("matchfile() failed: " + str(_read_cstr(Cerrmsg)))

        if Ccin[0] == -1:       # Error occurred
            if Ccout[0] == 2:
                raise ValueError("invalid encoder")
            elif Ccout[0] == 3:
                raise ValueError(str(_read_cstr(Cerrmsg))) # file i/o error
            elif Ccout[0] == 4:
                raise ValueError("invalid compiled pattern (already freed?)")
            else:
                raise ValueError("unknown error caused matchfile to fail")
        return Ccin[0], Ccout[0], Ccerr[0]

    def read_rcfile(self, filename=None):
        Cfile_exists = ffi.new("int *")
        if filename is None:
            filename_arg = _new_cstr()
        else:
            filename_arg = _new_cstr(filename)
        Coptions = _new_cstr()
        Cmessages = _new_cstr()
        ok = _lib.rosie_read_rcfile(self.engine, filename_arg, Cfile_exists, Coptions, Cmessages)
        if ok != 0:
            raise RuntimeError("read_rcfile() failed (please report this as a bug)")
        messages = _read_cstr(Cmessages)
        messages = messages and json.loads(messages)
        if Cfile_exists[0] == 0:
            return None, messages
        # else file existed and was read
        options = _read_cstr(Coptions)
        if options:
            return json.loads(options), messages
        # else: file existed, but some problems processing it
        return False, messages

    def execute_rcfile(self, filename=None):
        Cfile_exists = ffi.new("int *")
        Cno_errors = ffi.new("int *")
        if filename is None:
            filename_arg = _new_cstr()
        else:
            filename_arg = _new_cstr(filename)
        Cmessages = _new_cstr()
        ok = _lib.rosie_execute_rcfile(self.engine, filename_arg, Cfile_exists, Cno_errors, Cmessages)
        if ok != 0:
            raise RuntimeError("execute_rcfile() failed (please report this as a bug)")
        messages = _read_cstr(Cmessages)
        messages = messages and json.loads(messages)
        if Cfile_exists[0] == 0:
            return None, messages
        # else: file existed
        if Cno_errors[0] == 1:
            return True, messages
        # else: some problems processing it
        return False, messages

    # -----------------------------------------------------------------------------
    # Functions that return a parse tree or fragments of one
    # -----------------------------------------------------------------------------

    def parse_expression(self, exp):
        Cexp = _new_cstr(exp)
        Cparsetree = _new_cstr()
        Cmessages = _new_cstr()
        ok = _lib.rosie_parse_expression(self.engine, Cexp, Cparsetree, Cmessages)
        if ok != 0:
            raise RuntimeError("parse_expression failed (please report this as a bug)")
        return _read_cstr(Cparsetree), _read_cstr(Cmessages)
        
    def parse_block(self, block):
        Cexp = _new_cstr(block)
        Cparsetree = _new_cstr()
        Cmessages = _new_cstr()
        ok = _lib.rosie_parse_block(self.engine, Cexp, Cparsetree, Cmessages)
        if ok != 0:
            raise RuntimeError("parse_block failed (please report this as a bug)")
        return _read_cstr(Cparsetree), _read_cstr(Cmessages)
        
    def expression_refs(self, exp):
        Cexp = _new_cstr(exp)
        Crefs = _new_cstr()
        Cmessages = _new_cstr()
        ok = _lib.rosie_expression_refs(self.engine, Cexp, Crefs, Cmessages)
        if ok != 0:
            raise RuntimeError("expression_refs failed (please report this as a bug)")
        return _read_cstr(Crefs), _read_cstr(Cmessages)
        
    def block_refs(self, block):
        Cexp = _new_cstr(block)
        Crefs = _new_cstr()
        Cmessages = _new_cstr()
        ok = _lib.rosie_block_refs(self.engine, Cexp, Crefs, Cmessages)
        if ok != 0:
            raise RuntimeError("block_refs failed (please report this as a bug)")
        return _read_cstr(Crefs), _read_cstr(Cmessages)
        
    def expression_deps(self, exp):
        Cexp = _new_cstr(exp)
        Cdeps = _new_cstr()
        Cmessages = _new_cstr()
        ok = _lib.rosie_expression_deps(self.engine, Cexp, Cdeps, Cmessages)
        if ok != 0:
            raise RuntimeError("expression_deps failed (please report this as a bug)")
        return _read_cstr(Cdeps), _read_cstr(Cmessages)
        
    def block_deps(self, block):
        Cexp = _new_cstr(block)
        Cdeps = _new_cstr()
        Cmessages = _new_cstr()
        ok = _lib.rosie_block_deps(self.engine, Cexp, Cdeps, Cmessages)
        if ok != 0:
            raise RuntimeError("block_deps failed (please report this as a bug)")
        return _read_cstr(Cdeps), _read_cstr(Cmessages)

    # -----------------------------------------------------------------------------
    # Functions for reading and modifying various engine settings
    # -----------------------------------------------------------------------------

    def libpath(self, libpath=None):
        if libpath:
            libpath_arg = _new_cstr(libpath)
        else:
            libpath_arg = _new_cstr()
        ok = _lib.rosie_libpath(self.engine, libpath_arg)
        if ok != 0:
            raise RuntimeError("libpath() failed (please report this as a bug)")
        return _read_cstr(libpath_arg) if libpath is None else None

    def alloc_limit(self, newlimit=None):
        limit_arg = ffi.new("int *")
        usage_arg = ffi.new("int *")
        if newlimit is None:
            limit_arg[0] = -1   # query
        else:
            if (newlimit != 0) and (newlimit < 8192):
                raise ValueError("new allocation limit must be 8192 KB or higher (or zero for unlimited)")
            limit_arg = ffi.new("int *")
            limit_arg[0] = newlimit
        ok = _lib.rosie_alloc_limit(self.engine, limit_arg, usage_arg)
        if ok != 0:
            raise RuntimeError("alloc_limit() failed (please report this as a bug)")
        return limit_arg[0], usage_arg[0]

    def __del__(self):
        if hasattr(self, 'engine') and (self.engine != ffi.NULL):
            e = self.engine
            self.engine = ffi.NULL
            _lib.rosie_finalize(e)

# -----------------------------------------------------------------------------

class rplx(object):    
    def __init__(self, engine):
        self.id = ffi.new("int *")
        self.engine = engine
        
    def __del__(self):
        if self.id[0] and self.engine.engine:
            _lib.rosie_free_rplx(self.engine.engine, self.id[0])

    def maybe_valid(self):
        return self.id[0] != 0

    def valid(self):
        return self.maybe_valid() and \
            self.engine.engine and \
            isinstance(self.engine, engine)

    
# -----------------------------------------------------------------------------




