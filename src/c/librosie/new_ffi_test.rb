# gem install ffi

require 'ffi'
require 'json'

$: << "."                       # temporary: add "." to the library search path
require 'rosie'

Rosie.initialize("/Users/jjennings/Work/Dev/rosie-pattern-language")

config_string = Rosie.CString_from_string("{\"name\":\"Ruby engine\"}")
print "config_string string: ", config_string[:ptr].read_string_length(config_string[:len]), "\n"
print "config_string length: ", config_string[:len], "\n"
print "config_string struct size: ", Rosie::CString.size, "\n"

ignored = Rosie::CString_from_string("ignored")

# foo2 = Rosie.testbyref(ignored.pointer)
# foo1 = Rosie.testbyvalue(ignored)

# maybe_Rosie::CString = Rosie.testretstring(ignored.pointer)
# print "RETURNED Rosie::CString len is: ", maybe_Rosie::CString[:len], "; value is: ", maybe_Rosie::CString[:ptr].read_string, "\n"
# Rosie.free_string(maybe_Rosie::CString)

retval = Rosie.new_engine(config_string.pointer)
print "number of strings returned from api call is: ", retval[:n], "\n"
ptr_array = FFI::Pointer.new(FFI::Pointer, retval[:ptr]).read_array_of_pointer(retval[:n])
code = Rosie::CString.new ptr_array[0]
if code[:ptr].read_string() != "true" then
  msg = Rosie::CString.new ptr_array[1]
  print "Error calling new_engine: " + msg[:ptr].read_string_length(msg[:len])
  exit -1
else
  eid_string = Rosie::CString.new ptr_array[1]
  eid = eid_string[:ptr].read_string_length(eid_string[:len])
  print "eid is: ", eid, "\n"
end
Rosie.free_stringArray(retval)
eid_string = Rosie::CString_from_string(eid)

config_js = "{\"expression\" : \"\\\"ign\\\"\", \"encode\" : \"json\"}"
print "config_js is: ", config_js, "\n"

config_string = Rosie::CString_from_string(config_js)

def print_string_array(retval)
  print "number of strings returned from api call is: ", retval[:n], "\n"
  ptr_array = FFI::Pointer.new(FFI::Pointer, retval[:ptr]).read_array_of_pointer(retval[:n])
  for i in 0..(retval[:n]-1) do
    str = Rosie::CString.new ptr_array[i]
    print "  [", i, "] len=", str[:len], ", ptr=", str[:ptr].read_string_length(str[:len]), "\n"
  end
end

def string_array_from_CStringArray(retval)
  ptr_array = FFI::Pointer.new(FFI::Pointer, retval[:ptr]).read_array_of_pointer(retval[:n])
  strings = []
  for i in 0..(retval[:n]-1) do
    cstr = Rosie::CString.new ptr_array[i]
    strings[i] = cstr[:ptr].read_string_length(cstr[:len])
  end
  return strings
end

retval = Rosie.rosie_api("configure_engine", eid_string, config_string)
print_string_array(retval)
Rosie.free_stringArray(retval)

retval = Rosie.rosie_api("inspect_engine", eid_string, ignored)
print_string_array(retval)
Rosie.free_stringArray(retval)

retval = Rosie.rosie_api("match", eid_string, ignored)
print_string_array(retval)
Rosie.free_stringArray(retval)

retval = Rosie.rosie_api("match", eid_string, config_string)
print_string_array(retval)
Rosie.free_stringArray(retval)

config_string = Rosie::CString_from_string("This is NOT valid json")
retval = Rosie.new_engine(config_string.pointer)
print_string_array(retval)
Rosie.free_stringArray(retval)

retval = Rosie.rosie_api("load_manifest", eid_string, config_string)
print_string_array(retval)
Rosie.free_stringArray(retval)

retval = Rosie.rosie_api("configure_engine", eid_string, config_string)
print_string_array(retval)
Rosie.free_stringArray(retval)

# Loop test prep

test = Rosie::CString_from_string("$sys/MANIFEST")
print "TEST: len=", test[:len], "\n"
print "TEST: string=", test[:ptr].read_string, "\n"

retval = Rosie.rosie_api("load_manifest", eid_string, test)
print_string_array(retval)
Rosie.free_stringArray(retval)

config_js = "{\"expression\" : \"[:digit:]+\", \"encode\" : \"json\"}"
print "config_js is: ", config_js, "\n"

config_string = Rosie::CString_from_string(config_js)
retval = Rosie.rosie_api("configure_engine", eid_string, config_string)
print_string_array(retval)
Rosie.free_stringArray(retval)

# Loop test

foo = Rosie::CString_from_string("1239999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999")
retval = Rosie.rosie_api "match", eid_string, foo
retval_SAVE = retval

call_rosie = true

print "Looping..."
M = 1000000
for i in 0..5*M do
#for i in 0..0 do
  if call_rosie then
    retval = Rosie.rosie_api "match", eid_string, foo
  else
    retval = Rosie::CStringArray.new; retval[:n] = retval_SAVE[:n]; retval[:ptr] = retval_SAVE[:ptr]
  end
  strings = string_array_from_Rosie::CStringArray(retval)
  code = strings[0]
  if code != "true" then
    print "Error code returned from match api"
  end
  json_string = strings[1]
  if call_rosie then
    Rosie.free_stringArray(retval)
  end
  # if code=="true" then
  #   print "Successful call to match\n"
  # else
  #   print "Call to match FAILED\n"
  # end
  #print json_string, "\n"
  obj_to_return_to_caller = JSON.parse(json_string)
end

print " done.\n"
