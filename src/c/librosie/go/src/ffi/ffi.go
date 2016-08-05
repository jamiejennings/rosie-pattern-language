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
import "encoding/json"
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
	cfg := gostring_to_structStringptr("{\"expression\":\"[:digit:]+\", \"encode\":\"json\"}")
	a, err = C.new_engine(cfg)
	retval := structString_to_GoString(*C.string_array_ref(a,0))
	eid := structString_to_GoString(*C.string_array_ref(a,1))
	fmt.Printf("Code from new_engine: %s\n", retval)
	fmt.Printf("Eid from new_engine: %s\n", eid)

	eid_string := C.new_string_ptr(C.int(len(eid)), C.CString(eid))
	fmt.Printf("**** eid_string: len=%d, ptr=%s\n",
		eid_string.len, C.GoStringN(C.to_char_ptr(eid_string.ptr), C.int(eid_string.len)))
	C.free_stringArray(a)

	a, err = C.inspect_engine(eid_string)
	retval = structString_to_GoString(*C.string_array_ref(a,0))
	fmt.Printf("Code from inspect_engine: %s\n", retval)
	fmt.Printf("Config from inspect_engine: %s\n", structString_to_GoString(*C.string_array_ref(a,1)))
	C.free_stringArray(a)

	var foo string = "1239999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999"
	foo_string := C.new_string_ptr(C.int(len(foo)), C.CString(foo))

	a, err = C.match(eid_string, foo_string)
	retval = structString_to_GoString(*C.string_array_ref(a,0))
	fmt.Printf("Code from match: %s\n", retval)
	fmt.Printf("Data|false from match: %s\n", structString_to_GoString(*C.string_array_ref(a,1)))
	fmt.Printf("Leftover chars from match: %s\n", structString_to_GoString(*C.string_array_ref(a,2)))

// Loop prep

//	var M int = 1000000
	var M int = 1
	var r C.struct_stringArray
	var code, js_str string

	fmt.Printf("Looping...")
	for i:=0; i<5*M; i++ {
		r = C.match(eid_string, foo_string)
		code = structString_to_GoString(*C.string_array_ref(r,0))
		js_str = structString_to_GoString(*C.string_array_ref(r,1))
		if code != "true" {
			fmt.Printf("Error in match: %s\n", js_str)
		} else {
			fmt.Printf("Code from match: %s\n", code)
			fmt.Printf("Data|false from match: %s\n", js_str)
			fmt.Printf("Leftover chars from match: %s\n", structString_to_GoString(*C.string_array_ref(a,2)))
			var retvals map[string]map[string]interface{}
			err = json.Unmarshal([]byte(js_str), &retvals)
			if err != nil {
				fmt.Println("JSON parse error:", err)
			}
			// TODO:
			//  print JSON table
			fmt.Printf("Match table: %s\n", retvals)
			fmt.Printf("Text from match table: %s\n", retvals["*"]["text"])
			fmt.Printf("Pos from match table: %f\n", retvals["*"]["pos"].(float64))
			if retvals["*"]["subs"] != nil {
				fmt.Printf("Subs from match table: %s\n", retvals["*"]["subs"].(string))
			} else { fmt.Printf("No subs from match table.\n")
			}
		}
		C.free_stringArray(r);
	}
	fmt.Printf(" done.\n");

	C.free_stringArray(a)
	_, err = C.delete_engine(eid_string)
	if (err!=nil) { fmt.Printf("Err field from delete_engine: %s\n", err) }
	C.free_string_ptr(eid_string);
	C.finalize();

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
