

//
// npm install ffi
//

var ffi = require("ffi");
 
var libm = new ffi.Library("libm", { "ceil": [ "double", [ "double" ] ] });
console.log(libm.ceil(1.5)); // 2 
 
// You can also access just functions in the current process by passing a null 
var current = new ffi.Library(null, { "atoi": [ "int32", [ "string" ] ] });
console.log(current.atoi("1234")); // 1234 
