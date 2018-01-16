//  -*- Mode: Go; -*-                                                 
// 
//  rosie.go
// 
//  © Copyright IBM Corporation 2017.
//  LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
//  AUTHOR: Jamie A. Jennings

// Package rosie contains functions for using Rosie Pattern Language
package rosie

// #cgo LDFLAGS: ${SRCDIR}/librosie.a -lm -ldl
// #include <stdlib.h>
// #include "librosie.h"
//
// char *to_char_ptr(uint8_t *buf) {
//   return (char *) buf;
// }
// uint8_t *to_uint8_ptr(char *buf) {
//   return (uint8_t *) buf;
// }
// int *new_int() { return (int *)malloc(sizeof(int)); }
//
// #cgo CFLAGS: -I./include
import "C"

//import "unsafe"
import "errors"
import "fmt"
import "runtime"
import "encoding/json"
//import "os"
//import "sort"
//import "strconv"

type (
	RosieString = C.struct_rosie_string
)

// goString converts a rosie string to a go string
func goString(cstr RosieString) string {
	return C.GoStringN(C.to_char_ptr(cstr.ptr), C.int(cstr.len))
}

// rosieString converts a go string to a rosie string
func rosieString(s string) RosieString {
	var cstr = C.rosie_new_string(C.to_uint8_ptr(C.CString(s)), C.size_t(len(s)))
	return cstr
}

func rosieStringPtr(s string) *RosieString {
	var cstr_ptr = C.rosie_new_string_ptr(C.to_uint8_ptr(C.CString(s)), C.size_t(len(s)))
	return cstr_ptr
}

type Engine struct {
 	ptr *C.struct_rosie_engine
}

// New constructs a fresh rosie pattern engine
func New(name string) (en *Engine, err error) {
	var messages C.struct_rosie_string
	var en_ptr *C.struct_rosie_engine
	en_ptr, err = C.rosie_new(&messages)
	if en_ptr == nil {
		var printable_message string
		if messages.ptr == nil || messages.len == 0 {
			printable_message = "initialization failed with an unknown error"
		} else {
			printable_message = goString(messages)
		}
		return nil, errors.New("rosie: " + printable_message)
	}
	engine := Engine{en_ptr}
	runtime.SetFinalizer(&engine, finalizeEngine)
	return &engine, nil
}


func finalizeEngine(en *Engine) {
	C.rosie_finalize(en.ptr)
}
		

type Configuration [] map[string] string

func (en *Engine) Config() (cfg Configuration, err error) {
	var data C.struct_rosie_string
 	ok, err := C.rosie_config(en.ptr, &data)
	if ok != 0 {
		return nil, err
	}
	err = json.Unmarshal([]byte(goString(data)), &cfg)
	if err != nil {
		return nil, err
	}
	return cfg, nil
}

type (
	Pattern = C.int
)

type (
	Messages = [] interface{}
)

func mungeMessages(Cmessages RosieString) (messages Messages, err error) {
	if Cmessages.ptr != nil {
		err := json.Unmarshal([]byte(goString(Cmessages)), &messages)
		fmt.Printf("*** err from Unmarshal is %v\n", err)
		fmt.Printf("*** input: %s\n", goString(Cmessages))
		if err != nil {
			return nil, err
		}
		if len(messages) != 0 {
			return messages, nil
		}
 	} 
	return nil, nil
}

func (en *Engine) Compile(exp string) (pat Pattern, messages Messages, err error) {
 	var CexpPtr = rosieStringPtr(exp)
	var Cmessages RosieString
	pat = C.int(0)

 	ok, err := C.rosie_compile(en.ptr, CexpPtr, &pat, &Cmessages)
 	if ok != 0 {
		return pat, nil, err
	}
	messages, err = mungeMessages(Cmessages)
	if err != nil {
		pat = C.int(0)
	}
	return pat, messages, err
}

// 	var foo string = "1111111111222222222211111111112222222222111111111122222222221111111111222222222211111111112222222222"
// 	foo_string := rosieString(foo)

// 	var match C.struct_rosie_matchresult
// 	json_encoder := C.CString("json")
// 	a, err := C.rosie_match(engine, pat, 1, json_encoder, &foo_string, &match)
// 	fmt.Println(a, err, match)
// 	fmt.Println(match.leftover, goString(match.data))
// 	// retval = goString(raw_match)
// 	// fmt.Printf("Return code from match: %s\n", retval)
// //	fmt.Printf("Data|false from match: %s\n", goString(*C.string_array_ref(a,1)))
// //	fmt.Printf("Leftover chars from match: %s\n", goString(*C.string_array_ref(a,2)))

// 	// var r C.struct_rosie_stringArray
// 	// var code, js_str string
// 	// var leftover int

// 	// foo = "1239999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999"
// 	// foo_string = C.rosie_new_string_ptr(C.int(len(foo)), C.CString(foo))

// 	// r = C.rosie_match(engine, foo_string, nil)
// 	// code = goString(*C.string_array_ref(r,0))
// 	// js_str = goString(*C.string_array_ref(r,1))
// 	// leftover, err = strconv.Atoi(goString(*C.string_array_ref(r,2)))
// 	// if code != "true" {
// 	// 	fmt.Printf("Error in match: %s\n", js_str)
// 	// } else {
// 	// 	fmt.Printf("Return code from match: %s\n", code)
// 	// 	fmt.Printf("Data|false from match: %s\n", js_str)
// 	// 	fmt.Printf("Leftover chars from match: %d\n", leftover)

// 	// 	var retvals map[string]map[string]interface{}
// 	// 	err = json.Unmarshal([]byte(js_str), &retvals)
// 	// 	if err != nil {
// 	// 		fmt.Println("JSON parse error:", err)
// 	// 	}
// 	// 	fmt.Printf("Match table: %s\n", retvals)
// 	// 	fmt.Printf("Text from match table: %s\n", retvals["*"]["text"])
// 	// 	fmt.Printf("Pos from match table: %d\n", int(retvals["*"]["pos"].(float64)))
// 	// 	if retvals["*"]["subs"] != nil {
// 	// 		fmt.Printf("Subs from match table: %s\n", retvals["*"]["subs"].(string))
// 	// 	} else {
// 	// 		fmt.Printf("No subs from match table.\n")
// 	// 	}
// 	// }
// 	// C.rosieL_free_stringArray(r)

// 	fmt.Printf("Exiting...\n");

// 	C.rosie_finalize(engine);


// }
