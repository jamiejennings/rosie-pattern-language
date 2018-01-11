//  -*- Mode: Go; -*-                                              
// 
//  rtest.go    Sample driver for librosie in go
// 
//  © Copyright IBM Corporation 2016, 2017, 2018.
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

	for i:=0; i<100; i++ {

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

	fmt.Printf("Exiting...\n");

	C.rosie_finalize(engine);


}
