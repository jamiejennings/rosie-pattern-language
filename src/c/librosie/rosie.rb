# coding: utf-8
#  -*- Mode: Ruby; -*-                                              
# 
#  rosie.rb
# 
#  © Copyright IBM Corporation 2016.
#  LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
#  AUTHOR: Jamie A. Jennings

require 'ffi'

module Rosie

  class CString < FFI::Struct
    layout :len, :uint32,
           :ptr, :pointer
  end

  class CStringArray < FFI::Struct
    layout :n, :uint32,
           :ptr, :pointer
  end

  extend FFI::Library
  ffi_convention :stdcall       # needed?
  ffi_lib_flags :now            # required so other shared objects can resolve names
  ffi_lib "./librosie.so"
  attach_function 'initialize', [ :string, CStringArray ], :pointer
  attach_function 'finalize', [ :pointer ], :void
  attach_function 'rosie_api', [ :pointer, :string, CString ], CStringArray.val # TEMPORARY
  attach_function 'match', [ :pointer, CString ], CStringArray.val
  attach_function 'configure_engine', [ :pointer, CString ], CStringArray.val
  attach_function 'inspect_engine', [ :pointer ], CStringArray.val
  attach_function 'free_stringArray', [ CStringArray.val ], :void

  def Rosie.CString_from_string(str)
    instance = CString.new
    instance[:len] = str.length
    instance[:ptr] = FFI::MemoryPointer.from_string(str)
    instance
  end

  










end

