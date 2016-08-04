//  -*- Mode: Go; -*-                                              
// 
//  ffi_test.go
// 
//  © Copyright IBM Corporation 2016.
//  LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
//  AUTHOR: Jamie A. Jennings


package main

// #cgo LDFLAGS: -L${SRCDIR}/libs ${SRCDIR}/libs/liblua.a
// #include <stdint.h>
// #include <stdarg.h>
// #include <stdlib.h>
// #include "librosie.h"
// #include "lauxlib.h"
// #include "lualib.h"
// struct string *new_string_ptr(int len, char *buf) {
//   struct string *cstr_ptr = malloc(sizeof(struct string));
//   cstr_ptr->len = (uint32_t) len;
//   uint8_t *abuf = (uint8_t *)buf; /*malloc(sizeof(uint8_t)*len);*/
//   cstr_ptr->ptr = abuf;
//   return cstr_ptr;
// }
// char *to_char_ptr(uint8_t *buf) {
//   return (char *) buf;
// }
// struct string *string_array_ref(struct stringArray a, int index) {
//   if (index > a.n) return NULL;
//   else return a.ptr[index];
// }
// #cgo CFLAGS: -std=gnu99 -shared -DROSIE_HOME="/Users/jjennings/Work/Dev/rosie-pattern-language" -I/Users/jjennings/Work/Dev/rosie-pattern-language/lua-5.3.2/include
import "C"

import "fmt"
//import "encoding/json"
//import "unsafe"

func structString_to_GoString(cstr C.struct_string) string {
	fmt.Printf("In structString_to_GoString: cstr.len = %d\n", cstr.len)
	return C.GoStringN(C.to_char_ptr(cstr.ptr), C.int(cstr.len))
}

func gostring_to_structStringptr(s string) *C.struct_string {
	var cstr_ptr = C.new_string_ptr(C.int(len(s)), C.CString(s))
	return cstr_ptr
}

func main() {
	fmt.Printf("Hello, world.\n")
	
//	var r C.struct_string
	
	ss := C.CString("/Users/jjennings/Work/Dev/rosie-pattern-language")
	i, err := C.initialize(ss)
	fmt.Printf("Return code from initialize was: %d\n", i)
	fmt.Printf("Err field returned by initialize was: %s\n", err)

	var a C.struct_stringArray
	cfg := gostring_to_structStringptr("null")
	a, err = C.new_engine(cfg)
	retval := structString_to_GoString(*C.string_array_ref(a,0))
	fmt.Printf("Code from new_engine: %s\n", retval)
	fmt.Printf("Eid from new_engine: %s\n", structString_to_GoString(*C.string_array_ref(a,1)))

	_, err = C.delete_engine(C.string_array_ref(a,1))
	if (err!=nil) { fmt.Printf("Err field from delete_engine: %s\n", err) }


	// var retvals [2]interface{}
	// err = json.Unmarshal([]byte(retval), &retvals)
	// if err != nil {
	// 	fmt.Println("JSON parse error:", err)
	// }
	// fmt.Printf("Success code: %t\n", retvals[0].(bool))
	// fmt.Printf("String returned: %s\n", retvals[1].(string))



	// eid := C.new_string_ptr(4, C.CString(retvals[1].(string)))
	// r, err = C.rosie_api(C.CString("inspect_engine", eid, cfg))
	// fmt.Printf("Result of inspect_engine was: %s\n", structString_to_GoString(r))


}
