# gem install ffi

require 'ffi'

class AP < FFI::AutoPointer
  def self.release(p)
    Libc.free(p)
  end
end

module Libc
  extend FFI::Library
  ffi_lib FFI::Library::LIBC
  attach_function 'puts', [ :string ], :int
  attach_function 'strcpy', [ :pointer, :string ], :pointer
  attach_function :malloc, [:size_t], AP
  attach_function :free, [ AP ], :void
end

print Libc.puts("Hello, World!"), "\n"



buffer = Libc.malloc("a".size() * 100)              # Max size of return string
retptr = Libc.strcpy(buffer, "Abcdef")
print (buffer.null? ? "<null string>" : buffer.read_string()), "\n"


