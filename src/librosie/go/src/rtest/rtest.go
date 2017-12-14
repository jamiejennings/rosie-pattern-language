//  -*- Mode: Go; -*-                                              
// 
//  rtest.go    Sample driver for librosie in go
// 
//  © Copyright IBM Corporation 2016, 2017.
//  LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
//  AUTHOR: Jamie A. Jennings


package main

import "rosie"

import "fmt"
import "os"
import "runtime"

func main() {
//	runtime.LockOSThread()
	
	fmt.Printf("Initializing Rosie... ")
	
	engine, err := rosie.New("hi")
	if engine == nil {
		fmt.Println(err)
		os.Exit(-1)
	}
	fmt.Printf("Engine is %v\n", engine)
	engine, err = rosie.New("bye")
	if err != nil {
		fmt.Println(err)
		os.Exit(-1)
	}
	fmt.Printf("And another engine: %v\n", engine)
	runtime.GC()
	runtime.GC()
	fmt.Printf("Engine is %v\n", engine)

	var cfg rosie.Configuration
 	err = engine.Config(&cfg)
	if err == nil {
		for _, entry := range cfg {
			fmt.Printf("%s = %s (%s)\n", entry["name"], entry["value"], entry["desc"])
		}
 	} else {
 		fmt.Printf("Return value from config was: %v\n", err)
 		os.Exit(-1)
 	}

	for i:=1; i<20; i++ {
		runtime.GC()
	
		exp := "[:digit:]+"
		pat, err := engine.Compile(exp)
		
		if err != nil {
			fmt.Println(pat, err)
			os.Exit(-1)
		} else {
			fmt.Println("Successfully compiled pattern", pat)
		}
	}

//	runtime.KeepAlive(engine) // Needed?
	
 	// var foo string = "1111111111222222222211111111112222222222111111111122222222221111111111222222222211111111112222222222"
 	// foo_string := rosieString(foo)

 	// var match C.struct_rosie_matchresult
 	// json_encoder := C.CString("json")
 	// a, err := C.rosie_match(engine, pat, 1, json_encoder, &foo_string, &match)
 	// fmt.Println(a, err, match)
 	// fmt.Println(match.leftover, structString_to_GoString(match.data))








	// retval = structString_to_GoString(raw_match)
	// fmt.Printf("Return code from match: %s\n", retval)
//	fmt.Printf("Data|false from match: %s\n", structString_to_GoString(*C.string_array_ref(a,1)))
//	fmt.Printf("Leftover chars from match: %s\n", structString_to_GoString(*C.string_array_ref(a,2)))

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

	fmt.Printf("Exiting...\n");

//	C.rosie_finalize(engine);


}
