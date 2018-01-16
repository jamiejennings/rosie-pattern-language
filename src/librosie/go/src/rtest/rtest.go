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

 	cfg, err := engine.Config()
	if err == nil {
		for _, entry := range cfg {
			fmt.Printf("%s = %s (%s)\n", entry["name"], entry["value"], entry["desc"])
		}
 	} else {
 		fmt.Printf("Return value from config was: %v\n", err)
 		os.Exit(-1)
 	}

	fmt.Println("The next compilation is expected to fail.")
	pat, msgs, err := engine.Compile("foo")
	if pat == 0 {
		fmt.Printf("And it failed as expected: pattern returned is %v\n", pat)
	} else {
		fmt.Printf("ERROR: received a valid pattern %v\n", pat)
		os.Exit(-1)
	}
	if msgs != nil {
		fmt.Println("Messages are: ", msgs)
	}


	for i:=0; i<10; i++ {

		runtime.GC()
	
		exp := "[:digit:]+"
		pat, msgs, err := engine.Compile(exp)

		if err != nil {
			fmt.Println(pat, err)
			os.Exit(-1)
		} else {
			if pat != 0 {
				fmt.Println("Successfully compiled pattern", pat)
			} else {
				fmt.Println("FAILED TO compile pattern", pat)
			}
			if msgs != nil {
				fmt.Println(msgs)
			}
		}
	}

	fmt.Printf("Exiting...\n");

}
