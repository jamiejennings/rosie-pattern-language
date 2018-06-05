# coding: utf-8
#  -*- Mode: Python; -*-                                              
# 
#  rosie.py     An interface to librosie from Python 2.7 and 3.6
# 
#  © Copyright IBM Corporation 2016, 2017, 2018.
#  LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
#  AUTHOR: Jamie A. Jennings

# TODO:
#
# - format the rosie errors
# 

from __future__ import unicode_literals, print_function

import json
from . import internal
from .adapt23 import *

# -----------------------------------------------------------------------------
# Rosie-specific

def librosie_path():
    return internal._librosie_path

# -----------------------------------------------------------------------------
# 

class engine (object):
    '''
    A Rosie pattern matching engine is used to load/import RPL code
    (patterns) and to do matching.  Create as many engines as you need.
    '''
    def __init__(self):
        self._engine = internal.engine()
    
    # -----------------------------------------------------------------------------
    # Compile an expression
    # -----------------------------------------------------------------------------

    def compile(self, exp):
        pat, errs = self._engine.compile(bytes23(exp))
        if not pat:
            raise_compile_error(exp, errs)
        return rplx(pat)

    # -----------------------------------------------------------------------------
    # Functions for matching and tracing (debugging)
    # -----------------------------------------------------------------------------

    def match(self, pattern, input, **kwargs):
        errs = None
        if isinstance(pattern, str) or isinstance(pattern, bytes):
            pattern = self.compile(pattern)
        else:
            raise TypeError('pattern not a string or bytes: ' + repr(pattern))
        return pattern.match(input, **kwargs)

#     def trace(self, pat, input, start, style):
#         if pat.id[0] == 0:
#             raise ValueError("invalid compiled pattern")
#         Cmatched = ffi.new("int *")
#         Cinput = _new_cstr(input)
#         Ctrace = _new_cstr()
#         ok = _lib.rosie_trace(self.engine, pat.id[0], start, style, Cinput, Cmatched, Ctrace)
#         if ok != 0:
#             raise RuntimeError("trace() failed (please report this as a bug): " + str(_read_cstr(Ctrace)))
#         if Ctrace.ptr == ffi.NULL:
#             if Ctrace.len == 2:
#                 raise ValueError("invalid trace style")
#             elif Ctrace.len == 1:
#                 raise ValueError("invalid compiled pattern")
#         matched = False if Cmatched[0]==0 else True
#         trace = _read_cstr(Ctrace)
#         return matched, trace

    # -----------------------------------------------------------------------------
    # Functions for loading statements/blocks/packages into an engine
    # -----------------------------------------------------------------------------

#     def load(self, src):
#         Cerrs = _new_cstr()
#         Csrc = _new_cstr(src)
#         Csuccess = ffi.new("int *")
#         Cpkgname = _new_cstr()
#         ok = _lib.rosie_load(self.engine, Csuccess, Csrc, Cpkgname, Cerrs)
#         if ok != 0:
#             raise RuntimeError("load() failed (please report this as a bug)")
#         errs = _read_cstr(Cerrs)
#         pkgname = _read_cstr(Cpkgname)
#         return Csuccess[0], pkgname, errs

#     def loadfile(self, fn):
#         Cerrs = _new_cstr()
#         Cfn = _new_cstr(fn)
#         Csuccess = ffi.new("int *")
#         Cpkgname = _new_cstr()
#         ok = _lib.rosie_loadfile(self.engine, Csuccess, Cfn, Cpkgname, Cerrs)
#         if ok != 0:
#             raise RuntimeError("loadfile() failed (please report this as a bug)")
#         errs = _read_cstr(Cerrs)
#         pkgname = _read_cstr(Cpkgname)
#         return Csuccess[0], pkgname, errs

#     def import_pkg(self, pkgname, as_name=None):
#         Cerrs = _new_cstr()
#         if as_name:
#             Cas_name = _new_cstr(as_name)
#         else:
#             Cas_name = ffi.NULL
#         Cpkgname = _new_cstr(pkgname)
#         Cactual_pkgname = _new_cstr()
#         Csuccess = ffi.new("int *")
#         ok = _lib.rosie_import(self.engine, Csuccess, Cpkgname, Cas_name, Cactual_pkgname, Cerrs)
#         if ok != 0:
#             raise RuntimeError("import() failed (please report this as a bug)")
#         actual_pkgname = _read_cstr(Cactual_pkgname) #if Cactual_pkgname.ptr != ffi.NULL else None
#         errs = _read_cstr(Cerrs)
#         return Csuccess[0], actual_pkgname, errs

#     def matchfile(self, pat, encoder,
#                   infile=None,  # stdin
#                   outfile=None, # stdout
#                   errfile=None, # stderr
#                   wholefile=False):
#         if pat.id[0] == 0:
#             raise ValueError("invalid compiled pattern")
#         Ccin = ffi.new("int *")
#         Ccout = ffi.new("int *")
#         Ccerr = ffi.new("int *")
#         wff = 1 if wholefile else 0
#         Cerrmsg = _new_cstr()
#         ok = _lib.rosie_matchfile(self.engine,
#                                  pat.id[0],
#                                  encoder,
#                                  wff,
#                                  infile or b"",
#                                  outfile or b"",
#                                  errfile or b"",
#                                  Ccin, Ccout, Ccerr, Cerrmsg)
#         if ok != 0:
#             raise RuntimeError("matchfile() failed: " + str(_read_cstr(Cerrmsg)))

#         if Ccin[0] == -1:       # Error occurred
#             if Ccout[0] == 2:
#                 raise ValueError("invalid encoder")
#             elif Ccout[0] == 3:
#                 raise ValueError(str(_read_cstr(Cerrmsg))) # file i/o error
#             elif Ccout[0] == 4:
#                 raise ValueError("invalid compiled pattern (already freed?)")
#             else:
#                 raise ValueError("unknown error caused matchfile to fail")
#         return Ccin[0], Ccout[0], Ccerr[0]

#     # -----------------------------------------------------------------------------
#     # Functions for reading and processing rcfile (init file) contents
#     # -----------------------------------------------------------------------------

#     def read_rcfile(self, filename=None):
#         Cfile_exists = ffi.new("int *")
#         if filename is None:
#             filename_arg = _new_cstr()
#         else:
#             filename_arg = _new_cstr(filename)
#         Coptions = _new_cstr()
#         Cmessages = _new_cstr()
#         ok = _lib.rosie_read_rcfile(self.engine, filename_arg, Cfile_exists, Coptions, Cmessages)
#         if ok != 0:
#             raise RuntimeError("read_rcfile() failed (please report this as a bug)")
#         messages = _read_cstr(Cmessages)
#         messages = messages and json.loads(messages)
#         if Cfile_exists[0] == 0:
#             return None, messages
#         # else file existed and was read
#         options = _read_cstr(Coptions)
#         if options:
#             return json.loads(options), messages
#         # else: file existed, but some problems processing it
#         return False, messages

#     def execute_rcfile(self, filename=None):
#         Cfile_exists = ffi.new("int *")
#         Cno_errors = ffi.new("int *")
#         if filename is None:
#             filename_arg = _new_cstr()
#         else:
#             filename_arg = _new_cstr(filename)
#         Cmessages = _new_cstr()
#         ok = _lib.rosie_execute_rcfile(self.engine, filename_arg, Cfile_exists, Cno_errors, Cmessages)
#         if ok != 0:
#             raise RuntimeError("execute_rcfile() failed (please report this as a bug)")
#         messages = _read_cstr(Cmessages)
#         messages = messages and json.loads(messages)
#         if Cfile_exists[0] == 0:
#             return None, messages
#         # else: file existed
#         if Cno_errors[0] == 1:
#             return True, messages
#         # else: some problems processing it
#         return False, messages

#     # -----------------------------------------------------------------------------
#     # Functions that return a parse tree or fragments of one
#     # -----------------------------------------------------------------------------

#     def parse_expression(self, exp):
#         Cexp = _new_cstr(exp)
#         Cparsetree = _new_cstr()
#         Cmessages = _new_cstr()
#         ok = _lib.rosie_parse_expression(self.engine, Cexp, Cparsetree, Cmessages)
#         if ok != 0:
#             raise RuntimeError("parse_expression failed (please report this as a bug)")
#         return _read_cstr(Cparsetree), _read_cstr(Cmessages)
        
#     def parse_block(self, block):
#         Cexp = _new_cstr(block)
#         Cparsetree = _new_cstr()
#         Cmessages = _new_cstr()
#         ok = _lib.rosie_parse_block(self.engine, Cexp, Cparsetree, Cmessages)
#         if ok != 0:
#             raise RuntimeError("parse_block failed (please report this as a bug)")
#         return _read_cstr(Cparsetree), _read_cstr(Cmessages)
        
#     def expression_refs(self, exp):
#         Cexp = _new_cstr(exp)
#         Crefs = _new_cstr()
#         Cmessages = _new_cstr()
#         ok = _lib.rosie_expression_refs(self.engine, Cexp, Crefs, Cmessages)
#         if ok != 0:
#             raise RuntimeError("expression_refs failed (please report this as a bug)")
#         return _read_cstr(Crefs), _read_cstr(Cmessages)
        
#     def block_refs(self, block):
#         Cexp = _new_cstr(block)
#         Crefs = _new_cstr()
#         Cmessages = _new_cstr()
#         ok = _lib.rosie_block_refs(self.engine, Cexp, Crefs, Cmessages)
#         if ok != 0:
#             raise RuntimeError("block_refs failed (please report this as a bug)")
#         return _read_cstr(Crefs), _read_cstr(Cmessages)
        
#     def expression_deps(self, exp):
#         Cexp = _new_cstr(exp)
#         Cdeps = _new_cstr()
#         Cmessages = _new_cstr()
#         ok = _lib.rosie_expression_deps(self.engine, Cexp, Cdeps, Cmessages)
#         if ok != 0:
#             raise RuntimeError("expression_deps failed (please report this as a bug)")
#         return _read_cstr(Cdeps), _read_cstr(Cmessages)
        
#     def block_deps(self, block):
#         Cexp = _new_cstr(block)
#         Cdeps = _new_cstr()
#         Cmessages = _new_cstr()
#         ok = _lib.rosie_block_deps(self.engine, Cexp, Cdeps, Cmessages)
#         if ok != 0:
#             raise RuntimeError("block_deps failed (please report this as a bug)")
#         return _read_cstr(Cdeps), _read_cstr(Cmessages)

#     # -----------------------------------------------------------------------------
#     # Functions for reading and modifying various engine settings
#     # -----------------------------------------------------------------------------

#     def config(self):
#         Cresp = _new_cstr()
#         ok = _lib.rosie_config(self.engine, Cresp)
#         if ok != 0:
#             raise RuntimeError("config() failed (please report this as a bug)")
#         resp = _read_cstr(Cresp)
#         return resp

#     def libpath(self, libpath=None):
#         if libpath:
#             libpath_arg = _new_cstr(libpath)
#         else:
#             libpath_arg = _new_cstr()
#         ok = _lib.rosie_libpath(self.engine, libpath_arg)
#         if ok != 0:
#             raise RuntimeError("libpath() failed (please report this as a bug)")
#         return _read_cstr(libpath_arg) if libpath is None else None

#     def alloc_limit(self, newlimit=None):
#         limit_arg = ffi.new("int *")
#         usage_arg = ffi.new("int *")
#         if newlimit is None:
#             limit_arg[0] = -1   # query
#         else:
#             if (newlimit != 0) and (newlimit < 8192):
#                 raise ValueError("new allocation limit must be 8192 KB or higher (or zero for unlimited)")
#             limit_arg = ffi.new("int *")
#             limit_arg[0] = newlimit
#         ok = _lib.rosie_alloc_limit(self.engine, limit_arg, usage_arg)
#         if ok != 0:
#             raise RuntimeError("alloc_limit() failed (please report this as a bug)")
#         return limit_arg[0], usage_arg[0]

#     def __del__(self):
#         if hasattr(self, 'engine') and (self.engine != ffi.NULL):
#             e = self.engine
#             self.engine = ffi.NULL
#             _lib.rosie_finalize(e)

# -----------------------------------------------------------------------------

def raise_compile_error(expression, errs):
    raise RuntimeError('RPL compilation error:\n{}'.format(errs))

class rplx(object):    
    def __init__(self, internal_rplx):
        self._internal_rplx = internal_rplx
            
    def match(self, input, **kwargs):
        start = kwargs['start'] if 'start' in kwargs else 1
        encoder = kwargs['encoder'] if 'encoder' in kwargs else 'json'
        m, l, a, _, _ = self._internal_rplx.engine.match(self._internal_rplx,
                                                         bytes23(input),
                                                         start,
                                                         bytes23(encoder))
        if m == False:
            return False
        match_value = m if 'encoder' in kwargs else json.loads(m)
        return {'match': match_value, 'leftover': l, 'abend': (a == 1)}
    
# -----------------------------------------------------------------------------
