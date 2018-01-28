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

func assert(cond bool, msg string) {
	if !cond {
		fmt.Printf("* ASSERTION FAILED: %s\n", msg)
	}
}

func main() {

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
	if pat != nil {
		fmt.Printf("And it failed as expected: pattern returned is invalid\n")
		fmt.Println("Messages are: ", msgs)
	} else {
		fmt.Printf("ERROR: received a valid pattern %v\n", pat)
		os.Exit(-1)
	}

	for i:=0; i<4; i++ {

		runtime.GC()
	
		exp := "[:digit:]+"
		pat, msgs, err := engine.Compile(exp)

		if err != nil {
			fmt.Println(pat, err)
			os.Exit(-1)
		} else {
			if pat != nil {
				fmt.Println("Successfully compiled pattern", pat)
			} else {
				fmt.Println("FAILED TO compile pattern", pat)
			}
			if msgs != nil {
				fmt.Println(msgs)
			}
		}

		var match *rosie.Match
		if i%2 == 0 {
			match, err = pat.MatchString("12345")
		} else {
			match, err = pat.MatchString("kjh12345")
		}
		fmt.Println(match, err)
		if match.Data == nil {
			fmt.Println("Match FAILED")
		} else {
			fmt.Println("Match succeeded")
		}
	}

	// Load string

	fmt.Println("About to load a string")
	ok, pkgname, msgs, err := engine.LoadString("w = [:alpha:]+")
	fmt.Println(ok, pkgname, msgs, err)
	assert(ok, "string failed to load")
	assert(pkgname == "", "loading string returned a package???")
	assert(len(msgs) == 0, "loading this string should not have produced any messages")
	assert(err==nil, "err!!")

	fmt.Println("About to load a string that should fail to load")
	ok, pkgname, msgs, err = engine.LoadString("w = [aa]+")
	fmt.Println(ok, pkgname, msgs, err)
	assert(!ok, "string loaded but should have failed")
	assert(pkgname == "", "loading string returned a package???")
	assert(len(msgs) != 0, "loading this string should have produced some messages")
	assert(err==nil, "err!!")

	// Load file
	
	fmt.Println("About to load a file")
	ok, pkgname, msgs, err = engine.LoadFile("test.rpl")
	fmt.Println(ok, pkgname, msgs, err)
	assert(ok, "file failed to load")
	assert(pkgname == "test", "loading file did not return its package name")
	assert(len(msgs) == 0, "loading this file should not have produced any messages")
	assert(err==nil, "err!!")

	fmt.Println("About to load a file that should fail to load")
	ok, pkgname, msgs, err = engine.LoadFile("test.foobar")
	fmt.Println(ok, pkgname, msgs, err)
	assert(!ok, "file loaded but should have failed")
	assert(pkgname == "", "loading failed file returned a package???")
	assert(len(msgs) != 0, "loading this file should have produced some messages")
	assert(err==nil, "err!!")

	// Import
	
	fmt.Println("About to import a package")
	ok, pkgname, msgs, err = engine.ImportPkg("num")
	fmt.Println(ok, pkgname, msgs, err)
	assert(ok, "import failed")
	assert(pkgname == "num", "importing file did not return its package name")
	assert(len(msgs) == 0, "importing this file should not have produced any messages")
	assert(err==nil, "err!!")

	fmt.Println("About to import a package that should fail to load")
	ok, pkgname, msgs, err = engine.ImportPkg("foobarbaz")
	fmt.Println(ok, pkgname, msgs, err)
	assert(!ok, "file imported but should have failed")
	assert(pkgname == "", "importing failed file returned a package???")
	assert(len(msgs) != 0, "importing this file should have produced some messages")
	assert(err==nil, "err!!")

	// Import as
	
	fmt.Println("About to import a package under another name")
	ok, pkgname, msgs, err = engine.ImportPkgAs("net", "NET")
	fmt.Println(ok, pkgname, msgs, err)
	assert(ok, "import 'as' failed")
	assert(pkgname == "net", "importing file 'as' did not return its package name")
	assert(len(msgs) == 0, "importing this file 'as' should not have produced any messages")
	assert(err==nil, "err!!")

	fmt.Println("About to import a package under another name that should fail to load")
	ok, pkgname, msgs, err = engine.ImportPkgAs("foobarbaz", "foo")
	fmt.Println(ok, pkgname, msgs, err)
	assert(!ok, "file imported 'as' but should have failed")
	assert(pkgname == "", "importing 'as' failed file returned a package???")
	assert(len(msgs) != 0, "importing this file 'as' should have produced some messages")
	assert(err==nil, "err!!")




	fmt.Println("About to try getting and setting the engine's libpath")
	
	libpath, err := engine.GetLibpath()
	assert(err==nil, "err!!")
	fmt.Printf("engine libpath is %s\n", libpath)

	err = engine.SetLibpath("foo")
	assert(err==nil, "err!!")

	libpath, err = engine.GetLibpath()
	assert(err==nil, "err!!")
	assert(libpath=="foo", "did not set libpath correctly")
	fmt.Printf("engine libpath has been set to %s\n", libpath)

	
	fmt.Printf("Exiting...\n");

}
