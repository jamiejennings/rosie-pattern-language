//  -*- Mode: Javascript; -*-                                      
// 
//  rtest.js
// 
//  © Copyright IBM Corporation 2016.
//  LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
//  AUTHOR: Jamie A. Jennings

//
// npm install ffi
// npm install ref-array
//

var debug = require("debug");

var ffi = require("ffi");
var ref = require('ref');
var Struct = require('ref-struct');
var ArrayType = require('ref-array')

var DynamicLibrary = require('./node_modules/ffi/lib/dynamic_library'),
    ForeignFunction = require('./node_modules/ffi/lib/foreign_function')


var MyCString = Struct({
    'len': 'uint32',
    'ptr': ref.refType('CString')
});

var MyCStringArray = Struct({
    'n': 'uint32',
    'ptr': ref.refType(ref.refType(MyCString))
});

var MyCStringPtr = ref.refType(MyCString)
var MyCStringArrayPtr = ref.refType(MyCStringArray)

var RTLD_NOW = ffi.DynamicLibrary.FLAGS.RTLD_NOW;
var RTLD_GLOBAL = ffi.DynamicLibrary.FLAGS.RTLD_GLOBAL;
var mode = RTLD_NOW | RTLD_GLOBAL;

var RosieLib = new DynamicLibrary('librosie.so' || null, mode);

var funcs = {
    'clear_environment': [ MyCStringArray, ['pointer', MyCStringPtr] ],
    'match': [ MyCStringArray, ['pointer', MyCStringPtr, MyCStringPtr] ],
    'get_environment': [ MyCStringArray, ['pointer', MyCStringPtr] ],
    'load_manifest': [ MyCStringArray, ['pointer', MyCStringPtr] ],
    'load_file': [ MyCStringArray, ['pointer', MyCStringPtr] ],
    'configure_engine': [  MyCStringArray, ['pointer', MyCStringPtr] ],
    'load_string': [ MyCStringArray, ['pointer', MyCStringPtr] ],
    'info': [ MyCStringArray, ['pointer'] ],
    'inspect_engine': [ MyCStringArray, ['pointer'] ],
    'eval': [ MyCStringArray, ['pointer', MyCStringPtr, MyCStringPtr] ],
    'eval_file': [ MyCStringArray, ['pointer', MyCStringPtr, MyCStringPtr, MyCStringPtr, MyCStringPtr] ],
    'match_file': [ MyCStringArray, ['pointer', MyCStringPtr, MyCStringPtr, MyCStringPtr, MyCStringPtr] ],
    'set_match_exp_grep_TEMPORARY': [ MyCStringArray, ['pointer', MyCStringPtr] ],
    
    'initialize': [ 'pointer', [MyCStringPtr, MyCStringArrayPtr] ],
    'finalize': [ 'void', ['pointer'] ],
    
    'free_string': [ 'void', [ MyCString ] ],
    'free_string_ptr': [ 'void', [ MyCString ] ],
    'free_stringArray': [ 'void', [ MyCStringArray ] ],
    'free_stringArray_ptr': [ 'void', [ MyCStringArray ] ]
}

var Rosie = new ffi.Library;
Object.keys(funcs || {}).forEach(function (func) {
    debug('defining function', func)

    var fptr = RosieLib.get(func)
      , info = funcs[func]

    if (fptr.isNull()) {
      throw new Error('Library: "' + Libfile
        + '" returned NULL function pointer for "' + func + '"')
    }

    var resultType = info[0]
      , paramTypes = info[1]
      , fopts = info[2]
      , abi = fopts && fopts.abi
      , async = fopts && fopts.async
      , varargs = fopts && fopts.varargs

    if (varargs) {
      Rosie[func] = VariadicForeignFunction(fptr, resultType, paramTypes, abi)
    } else {
      var ff = ForeignFunction(fptr, resultType, paramTypes, abi)
      Rosie[func] = async ? ff.async : ff
    }
  })

function new_CString(str) {
    var cstr = new MyCString
    cstr.ptr = ref.allocCString(str)
    cstr.len = str.length
    return cstr
}

function extract_string_from_CString_ptr(cstr_ptr) {
    var cstr = ref.alloc(MyCString)
    cstr = cstr_ptr.deref()
    var buf = cstr.ptr.reinterpret(cstr.len)
    return buf.toString()
}    

function extract_string_from_array(stringarray, index) {
    var n = stringarray.n
    var p = stringarray.ptr
    if (index < n) {
	var cstr_ptr = ref.get(p, (index*ref.sizeof.pointer), MyCStringPtr)
	var str = extract_string_from_CString_ptr(cstr_ptr)
	return str
    }
    else return null
}

function print_array(retval) {
    var n = retval.n
    for (var i=0; i<n; i++) {
	var str = extract_string_from_array(retval, i)
	console.log("print_array: [", i, "] length =", str.length, " and value =", str)
    }
}

messages = new MyCStringArray
console.log("About to initialize Rosie")
var engine = Rosie.initialize(new_CString("/Users/jjennings/Dev/public/rosie-pattern-language").ref(), messages.ref())
console.log("Return value from initialize: ", engine)

var config = new_CString(
    JSON.stringify(
	{'name': 'js test engine', 'expression':'[:digit:]+', 'encode':false}
    ))

// Just a small test of the string conversion:
var buf = config.ptr.reinterpret(config.len)
console.log(config.ptr.length, config.len, buf.toString("utf8", 0, config.len))

var retval = ref.alloc(MyCStringArray)
retval = Rosie.configure_engine(engine, config.ref())
console.log("Return value from configure_engine is: ")
var code = extract_string_from_array(retval, 0)
print_array(retval)

retval = Rosie.inspect_engine(engine)
console.log("Return value from inspect_engine is: ")
print_array(retval)

// Loop prep

var manifest = new_CString("$sys/MANIFEST")
console.log("manifest: len =", manifest.len, "value =", manifest.ptr.toString())

retval = Rosie.load_manifest(engine, manifest.ref())
print_array(retval)
Rosie.free_stringArray(retval)

var config = new_CString("{\"expression\" : \"[:digit:]+\", \"encode\" : \"json\"}")

retval = Rosie.configure_engine(engine, config.ref())
print_array(retval)
Rosie.free_stringArray(retval)

var foo = new_CString("1239999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999")
var retval = Rosie.match(engine, foo.ref(), null)
print_array(retval)

code = extract_string_from_array(retval, 0)
if (code != "true") console.log("Error code returned from match api")
json_string = extract_string_from_array(retval, 1)
Rosie.free_stringArray(retval)
if (code=="true") console.log("Successful call to match")
else console.log("Call to match FAILED")
console.log(json_string)
obj_to_return_to_caller = JSON.parse(json_string)

console.log("Done.\n")
