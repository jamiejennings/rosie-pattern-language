//  -*- Mode: Go; -*-                                              
// 
//  ffi_test.go
// 
//  © Copyright IBM Corporation 2016.
//  LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
//  AUTHOR: Jamie A. Jennings


package main

// #include <stdint.h>
// #include <stdarg.h>
// #include <stdlib.h>
// #include "librosie.h"
// #include "lauxlib.h"
// #include "lualib.h"
// #cgo CFLAGS: -std=gnu99 -DROSIE_HOME="/Users/jjennings/Work/Dev/rosie-pattern-language"  -llibrosie
// #cgo LDFLAGS: -L${SRCDIR}
import "C"

import "fmt"


type CString struct {
	len uint32
	ptr *C.char
}

type CStringArray struct {
	len uint32
	ptr []*CString
}

// C data with explicit length to Go string
//func C.GoStringN(*C.char, C.int) string


func main() {
	fmt.Printf("Hello, world.\n")
	
}
