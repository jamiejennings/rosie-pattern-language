//  -*- Mode: Javascript; -*-                                      
// 
//  rtest.js
// 
//  © Copyright IBM Corporation 2016, 2017.
//  LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
//  AUTHOR: Jamie A. Jennings

// ON OS X:  export CXX=clang++
// npm install ffi
// npm install ref-array
// npm install debug

var rosie_home = process.env.ROSIE_HOME;
if (!rosie_home | rosie_home=="") {
    console.log("Environment variable ROSIE_HOME not set.  It must point to root of rosie directory.");
    process.exit(-1);
}

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

var RosieLib = new DynamicLibrary(rosie_home + '/ffi/librosie/librosie.so' || null, mode);

var funcs = {
    'rosieL_clear_environment': [ MyCStringArray, ['pointer', MyCStringPtr] ],
    'rosieL_match': [ MyCStringArray, ['pointer', MyCStringPtr, MyCStringPtr] ],
    'rosieL_get_environment': [ MyCStringArray, ['pointer', MyCStringPtr] ],
    'rosieL_load_manifest': [ MyCStringArray, ['pointer', MyCStringPtr] ],
    'rosieL_load_file': [ MyCStringArray, ['pointer', MyCStringPtr] ],
    'rosieL_configure_engine': [  MyCStringArray, ['pointer', MyCStringPtr] ],
    'rosieL_load_string': [ MyCStringArray, ['pointer', MyCStringPtr] ],
    'rosieL_info': [ MyCStringArray, ['pointer'] ],
    'rosieL_inspect_engine': [ MyCStringArray, ['pointer'] ],
    'rosieL_eval': [ MyCStringArray, ['pointer', MyCStringPtr, MyCStringPtr] ],
    'rosieL_eval_file': [ MyCStringArray, ['pointer', MyCStringPtr, MyCStringPtr, MyCStringPtr, MyCStringPtr] ],
    'rosieL_match_file': [ MyCStringArray, ['pointer', MyCStringPtr, MyCStringPtr, MyCStringPtr, MyCStringPtr] ],
    'rosieL_set_match_exp_grep_TEMPORARY': [ MyCStringArray, ['pointer', MyCStringPtr] ],
    
    'rosieL_initialize': [ 'pointer', [MyCStringPtr, MyCStringArrayPtr] ],
    'rosieL_finalize': [ 'void', ['pointer'] ],
    
    'rosieL_free_string': [ 'void', [ MyCString ] ],
    'rosieL_free_string_ptr': [ 'void', [ MyCString ] ],
    'rosieL_free_stringArray': [ 'void', [ MyCStringArray ] ],
    'rosieL_free_stringArray_ptr': [ 'void', [ MyCStringArray ] ]
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
var engine = Rosie.rosieL_initialize(new_CString(rosie_home).ref(), messages.ref())
console.log("Return value from initialize: ", engine)

var config = new_CString(
    JSON.stringify(
	{'name': 'js test engine', 'expression':'[:digit:]+', 'encode':false}
    ))

// Just a small test of the string conversion:
var buf = config.ptr.reinterpret(config.len)
console.log(config.ptr.length, config.len, buf.toString("utf8", 0, config.len))

var retval = ref.alloc(MyCStringArray)
retval = Rosie.rosieL_configure_engine(engine, config.ref())
console.log("Return value from configure_engine is: ")
var code = extract_string_from_array(retval, 0)
print_array(retval)

retval = Rosie.rosieL_inspect_engine(engine)
console.log("Return value from inspect_engine is: ")
print_array(retval)

// Loop prep

var manifest = new_CString("$sys/MANIFEST")
console.log("manifest: len =", manifest.len, "value =", manifest.ptr.toString())

retval = Rosie.rosieL_load_manifest(engine, manifest.ref())
print_array(retval)
Rosie.rosieL_free_stringArray(retval)

var config = new_CString("{\"expression\" : \"[:digit:]+\", \"encode\" : \"json\"}")

retval = Rosie.rosieL_configure_engine(engine, config.ref())
print_array(retval)
Rosie.rosieL_free_stringArray(retval)

var foo = new_CString("1239999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999")
var retval = Rosie.rosieL_match(engine, foo.ref(), null)
print_array(retval)

code = extract_string_from_array(retval, 0)
if (code != "true") console.log("Error code returned from match api")
json_string = extract_string_from_array(retval, 1)
Rosie.rosieL_free_stringArray(retval)
if (code=="true") console.log("Successful call to match")
else console.log("Call to match FAILED")
console.log(json_string)
obj_to_return_to_caller = JSON.parse(json_string)

Rosie.rosieL_finalize(engine)

console.log("Done.\n")
