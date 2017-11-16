//  -*- Mode: Go; -*-                                              
// 
//  rtest.go    Sample driver for librosie in go
// 
//  © Copyright IBM Corporation 2016, 2017.
//  LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
//  AUTHOR: Jamie A. Jennings


package main

// #cgo LDFLAGS: ${SRCDIR}/librosie.a -lm -ldl
// #include <assert.h>
// #include <signal.h>
// #include <stdio.h>
// #include <stdlib.h>
// #include <string.h>
// #include <stdarg.h>
// #include <dlfcn.h>
// #include <libgen.h>
// #include "librosie.h"
// char *to_char_ptr(uint8_t *buf) {
//   return (char *) buf;
// }
// uint8_t *to_uint8_ptr(char *buf) {
//   return (uint8_t *) buf;
// }
// #cgo CFLAGS: -std=gnu99 -I./include
import "C"

import "fmt"
//import "encoding/json"
import "os"
//import "strconv"

func structString_to_GoString(cstr C.struct_rosie_string) string {
	return C.GoStringN(C.to_char_ptr(cstr.ptr), C.int(cstr.len))
}

func gostring_to_structStringptr(s string) *C.struct_rosie_string {
	var cstr_ptr = C.rosie_new_string_ptr(C.to_uint8_ptr(C.CString(s)), C.size_t(len(s)))
	return cstr_ptr
}

func main() {
	fmt.Printf("Initializing Rosie... ")
	
	var messages C.struct_rosie_string
	
	engine, err := C.rosie_new(&messages)
	fmt.Printf("done.\n")
	if engine==nil {
		var printable_message string
		fmt.Printf("Return value from initialize was NULL!\n")
		fmt.Printf("Err field returned by initialize was: %s\n", err)
		if messages.ptr==nil {
			printable_message = "NO MESSAGE RETURNED"
		} else {
			printable_message = structString_to_GoString(messages)
		}
		fmt.Printf("Messages returned from initialize:\n%s\n", printable_message)
		os.Exit(-1)
	}

	// var a C.struct_rosie_stringArray
	// cfg := gostring_to_structStringptr("{\"expression\":\"[:digit:]+\", \"encode\":\"json\"}")
	// a, err = C.rosieL_configure_engine(engine, cfg)
	// retval := structString_to_GoString(*C.string_array_ref(a,0))
	// fmt.Printf("Return code from configure_engine: %s\n", retval)

	// a, err = C.rosieL_inspect_engine(engine)
	// retval = structString_to_GoString(*C.string_array_ref(a,0))
	// fmt.Printf("Return code from inspect_engine: %s\n", retval)
	// fmt.Printf("Config from inspect_engine: %s\n", structString_to_GoString(*C.string_array_ref(a,1)))
	// C.rosieL_free_stringArray(a)

	// var foo string = "1111111111222222222211111111112222222222111111111122222222221111111111222222222211111111112222222222"
	// foo_string := C.rosie_new_string_ptr(C.int(len(foo)), C.CString(foo))

	// a, err = C.rosie_match(engine, foo_string, nil)
	// retval = structString_to_GoString(*C.string_array_ref(a,0))
	// fmt.Printf("Return code from match: %s\n", retval)
	// fmt.Printf("Data|false from match: %s\n", structString_to_GoString(*C.string_array_ref(a,1)))
	// fmt.Printf("Leftover chars from match: %s\n", structString_to_GoString(*C.string_array_ref(a,2)))

	// var r C.struct_rosie_stringArray
	// var code, js_str string
	// var leftover int

	// foo = "1239999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999"
	// foo_string = C.rosie_new_string_ptr(C.int(len(foo)), C.CString(foo))

	// r = C.rosie_match(engine, foo_string, nil)
	// code = structString_to_GoString(*C.string_array_ref(r,0))
	// js_str = structString_to_GoString(*C.string_array_ref(r,1))
	// leftover, err = strconv.Atoi(structString_to_GoString(*C.string_array_ref(r,2)))
	// if code != "true" {
	// 	fmt.Printf("Error in match: %s\n", js_str)
	// } else {
	// 	fmt.Printf("Return code from match: %s\n", code)
	// 	fmt.Printf("Data|false from match: %s\n", js_str)
	// 	fmt.Printf("Leftover chars from match: %d\n", leftover)

	// 	var retvals map[string]map[string]interface{}
	// 	err = json.Unmarshal([]byte(js_str), &retvals)
	// 	if err != nil {
	// 		fmt.Println("JSON parse error:", err)
	// 	}
	// 	fmt.Printf("Match table: %s\n", retvals)
	// 	fmt.Printf("Text from match table: %s\n", retvals["*"]["text"])
	// 	fmt.Printf("Pos from match table: %d\n", int(retvals["*"]["pos"].(float64)))
	// 	if retvals["*"]["subs"] != nil {
	// 		fmt.Printf("Subs from match table: %s\n", retvals["*"]["subs"].(string))
	// 	} else {
	// 		fmt.Printf("No subs from match table.\n")
	// 	}
	// }
	// C.rosieL_free_stringArray(r)

	fmt.Printf(" done.\n");

	// C.rosie_finalize(engine);


}
