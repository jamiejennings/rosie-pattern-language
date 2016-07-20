# gem install ffi

require 'ffi'
require 'json'

class CString < FFI::Struct
  layout :len, :uint32,
         :ptr, :pointer
end

def CString_from_string(str)
  instance = CString.new
  instance[:len] = str.length
  instance[:ptr] = FFI::MemoryPointer.from_string(str)
  print "INIT FROM STRING: ", str, " whose length is: ", str.length, "\n"
  instance
end

class CStringArray < FFI::Struct
  layout :n, :uint32,
         :ptr, :pointer
end

class CStringArray2 < FFI::Struct
  layout :n, :uint32,
         :ptr, :pointer 
end

module Rosie
  extend FFI::Library
  ffi_convention :stdcall       # needed?
  ffi_lib_flags :now            # required so other shared objects can resolve names
  ffi_lib "./librosie.so"
  attach_function 'initialize', [ :string ], :void
  attach_function 'rosie_api', [ :string, CString, CString ], CString.val
  attach_function 'new_engine', [ CString ], CString.val
  attach_function 'free_string', [ CString.val ], :void
  attach_function 'testbyvalue', [ CString.val ], :uint32
  attach_function 'testbyref', [ :pointer ], :uint32
  attach_function 'testretstring', [ CString ], CString.val
  attach_function 'testretarray', [ CString.val ], CStringArray.val
  attach_function 'testretarray2', [ CString.val ], CStringArray2.val
end

s_array = Rosie.testretarray(CString_from_string("This string is not used for anything in this test."))
n = s_array[:n]
print "Number of CStrings returned: ", n, "\n"
ptr_array = FFI::Pointer.new(FFI::Pointer, s_array[:ptr]).read_array_of_pointer(n)
for i in 0..(n-1) do
  cstr = CString.new ptr_array[i]
  print cstr, "\t length is: ", cstr[:len], "\n"
  print "string ", i, ": ", cstr[:ptr].read_string_length(cstr[:len]), "\n"
end
print "\n"

## This approach (below) appears not to work.  Some info online suggests that arrays of structs are not supported in Ruby's ffi. 

# s_array = Rosie.testretarray2(CString_from_string("This string is not used for anything in this test."))
# n = s_array[:n]
# print "Number of CStrings returned: ", n, "\n"
# print "First CString: ", s_array[:ptr], "\n"
# # cstr_ptr = CString.new s_array[:ptr]
# # print "cstr_ptr: ", cstr_ptr, "\n"
# # print "cstr_ptr[:len]: ", cstr_ptr[:len], "\n"
# cstr_array = FFI::Pointer.new(FFI::Pointer, s_array[:ptr]).read_array_of_pointer(n)
# for i in 0..(n-1) do
#   cstr = CString.new cstr_array[i]
#   print cstr, "\t length is: ", cstr[:len], "\n"
#   print "string ", i, ": ", cstr[:ptr].read_string_length(cstr[:len]), "\n"
# end
# print "\n"



# Rosie.initialize("asldkasldk")

# config_string = CString_from_string("{\"name\":\"Ruby engine\"}")
# print "config_string string: ", config_string[:ptr].read_string_length(config_string[:len]), "\n"
# print "config_string length: ", config_string[:len], "\n"
# print "config_string struct size: ", CString.size, "\n"

# ignored = CString_from_string("ignored")
# foo2 = Rosie.testbyref(ignored.pointer)
# foo1 = Rosie.testbyvalue(ignored)

# maybe_CString = Rosie.testretstring(ignored.pointer)
# print "RETURNED CString len is: ", maybe_CString[:len], "; value is: ", maybe_CString[:ptr].read_string, "\n"
# Rosie.free_string(maybe_CString)

# eid_retval = Rosie.new_engine(config_string.pointer)
# print "LEN result of api call is: ", eid_retval[:len], "\n"
# retval_js = eid_retval[:ptr].read_string_length(eid_retval[:len])
# print "STRING result of api call is: ", retval_js, "\n"
# Rosie.free_string(eid_retval)

# retval = JSON.parse(retval_js)

# eid_string = CString_from_string(retval[1])
# print "eid_string value is: ", eid_string[:ptr].read_string_length(eid_string[:len]), "; eid_string len is: ", eid_string[:len], "\n"

# config_js = "{\"expression\" : \"\\\"ign\\\"\", \"encode\" : false}"
# print "config_js is: ", config_js, "\n"

# config_string = CString_from_string(config_js)

# retval = Rosie.rosie_api("configure_engine", eid_string, config_string)
# print retval[:ptr].read_string, "\n"
# Rosie.free_string(retval)
# retval = Rosie.rosie_api("inspect_engine", eid_string, ignored)
# print retval[:ptr].read_string, "\n"
# Rosie.free_string(retval)
# retval = Rosie.rosie_api("match", eid_string, ignored)
# print retval[:ptr].read_string, "\n"
# Rosie.free_string(retval)
# retval = Rosie.rosie_api("match", eid_string, config_string)
# print retval[:ptr].read_string, "\n"
# Rosie.free_string(retval)

# config_string = CString_from_string("This is NOT valid json")
# retval = Rosie.new_engine(config_string.pointer)
# print retval[:ptr].read_string, "\n"
# Rosie.free_string(retval)

# retval = Rosie.rosie_api("load_manifest", eid_string, config_string)
# print retval[:ptr].read_string, "\n"
# Rosie.free_string(retval)

# retval = Rosie.rosie_api("configure_engine", eid_string, config_string)
# print retval[:ptr].read_string, "\n"
# Rosie.free_string(retval)

# # Loop test prep

# test = CString_from_string("$sys/MANIFEST")
# print "TEST: len=", test[:len], "\n"
# print "TEST: string=", test[:ptr].read_string, "\n"

# retval = Rosie.rosie_api("load_manifest", eid_string, test)

# config_js = "{\"expression\" : \"[:digit:]+\", \"encode\" : false}"
# print "config_js is: ", config_js, "\n"

# config_string = CString_from_string(config_js)
# retval = Rosie.rosie_api("configure_engine", eid_string, config_string)
# print retval[:ptr].read_string, "\n"
# Rosie.free_string(retval)

# # Loop test

# foo = CString.new
# foo[:ptr] = FFI::MemoryPointer.from_string "123"
# foo[:len] = 3

# for i in 0..1000 do
#   retval = Rosie.rosie_api "match", eid_string, foo
#   json_string = retval[:ptr].read_string_length(retval[:len])
#   Rosie.free_string(retval)
# #  obj_to_return_to_caller = JSON.parse(json_string)
# end


