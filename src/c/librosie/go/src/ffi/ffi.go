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
// #cgo CFLAGS: -std=gnu99 -shared -DROSIE_HOME="/Users/jjennings/Work/Dev/rosie-pattern-language" -I/Users/jjennings/Work/Dev/rosie-pattern-language/lua-5.3.2/include
import "C"

import "fmt"
import "encoding/json"
import "unsafe"

// type CString struct {
// 	len uint32
// 	ptr *C.char
// }

// type CStringArray struct {
// 	len uint32
// 	ptr []*CString
// }

// C data with explicit length to Go string
//func C.GoStringN(*C.char, C.int) string
// Go string to C string
//func C.CString(string) *C.char

// var funcs = {'initialize': [ 'int', ['string']],
// 	     'new_engine': [ MyCString, [MyCStringPtr] ],
// 	     'rosie_api': [ MyCString, ['string', MyCStringPtr, MyCStringPtr] ],
// 	     'testbyref': [ 'int', [MyCStringPtr] ],
// 	     'testbyvalue': [ 'int', [MyCString] ],
// 	     'testretstring': [ MyCString, [MyCStringPtr] ],
// 	     'testretarray': [ MyCStringArray, [MyCString] ] }

// func toStructString(s string) C.struct_string {
// 	cstr := C.CString(s)
// 	ptr := [4]byte(unsafe.Pointer(cstr))
// 	return C.struct_string{C.uint32_t(len(s)), ptr}
// }

func structString_to_GoString(cstr C.struct_string) string {
	return C.GoStringN(C.to_char_ptr(cstr.ptr), C.int(cstr.len))
}

func gostring_to_structString(s string) C.struct_string {
	var cstr_ptr = C.new_string_ptr(C.int(len(s)), C.CString(s))
	return *cstr_ptr
}

func main() {
	fmt.Printf("Hello, world.\n")
	
	var r C.struct_string
	var a C.struct_string_array
	a, err := C.testretarray(gostring_to_structString("foobar"))
	fmt.Printf("testretarray returned: %v\n", a)

	var n int
	n = int(a.n)
	fmt.Printf("testretarray n: %d\n", n)

	size := int(unsafe.Sizeof(*a.ptr))
	fmt.Printf("size is %d\n", size)

	var cstrArray **C.struct_string = a.ptr
	// N.B. constant max size of slice:
        slice := (*[10]*C.struct_string)(unsafe.Pointer(cstrArray))[:n:n]
	fmt.Println(slice)
	
	for _, cstr_ptr := range slice {
		fmt.Println(structString_to_GoString(*cstr_ptr))
	}
	
	var len int
	var ptr *C.struct_string
	for i:=0; i<n; i++ {
		ptr = (*a.ptr)
		len = int(ptr.len)
		fmt.Printf("testretarray struct string %d len: %d\n", i, len)
		// fmt.Printf("testretarray struct string ptr: %s\n", structString_to_GoString(s))
	}
	
	ss := C.CString("adajdsajdkajdkas")
	_, err = C.initialize(ss)
	fmt.Printf("Err field returned by initialize was: %s\n", err)

	cfg := C.new_string_ptr(4, C.CString("null"))
	r, err = C.new_engine(cfg)
	retval := structString_to_GoString(r)
	fmt.Printf("Result of new_engine was: %s\n", retval)

	var retvals [2]interface{}
	err = json.Unmarshal([]byte(retval), &retvals)
	if err != nil {
		fmt.Println("JSON parse error:", err)
	}
	fmt.Printf("Success code: %t\n", retvals[0].(bool))
	fmt.Printf("String returned: %s\n", retvals[1].(string))

	// eid := C.new_string_ptr(4, C.CString(retvals[1].(string)))
	// r, err = C.rosie_api(C.CString("inspect_engine", eid, cfg))
	// fmt.Printf("Result of inspect_engine was: %s\n", structString_to_GoString(r))


}
