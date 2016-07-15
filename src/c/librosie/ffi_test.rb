# gem install ffi

require 'ffi'
require 'json'

class AP < FFI::AutoPointer
  def self.release(p)
    Libc.free(p)
  end
end

module Libc
  extend FFI::Library
  ffi_lib FFI::Library::LIBC
  attach_function 'puts', [ :string ], :int
  attach_function 'strlcpy', [ :pointer, :string, :size_t ], :pointer
  attach_function :malloc, [:size_t], AP
  attach_function :free, [ AP ], :void
end

print Libc.puts("Hello, World!"), "\n"

buffer = Libc.malloc("a".size() * 100)              # Max size of return string
retptr = Libc.strlcpy(buffer, "Abcdef", 100)
print (buffer.null? ? "<null string>" : buffer.read_string()), "\n"


module Rosie
  extend FFI::Library
  ffi_lib_flags :now                                # required so other shared objects can resolve names
  ffi_lib "./librosie.so"
  attach_function 'initialize', [ :string ], :void
  attach_function 'rosie_api', [ :string, :string, :string ], :int, :string
end

Rosie.initialize("asldkasldk")
ok, retval_js = Rosie.rosie_api("new_engine", "{\"name\":\"Ruby engine\"}", "")
print "Result of api call is: ", ok, "\n"
print "Second result of api call is: ", retval_js, "\n"
ok, retval_js = Rosie.rosie_api("inspect_engine", "", "")
print "Result of api call is: ", ok, "\n"

# retval = JSON.parse(retval_js)
