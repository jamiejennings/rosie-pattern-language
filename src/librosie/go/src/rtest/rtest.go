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

var errs = 0			// counter

func assert(cond bool, msg string) {
	if !cond {
		errs++
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

 	cfgs, err := engine.Config()
	if err == nil {
		for _, cfg := range cfgs {
			for _, entry := range cfg {
				fmt.Printf("%s = %s (%s)\n", entry["name"], entry["value"], entry["desc"])
			}
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


	fmt.Println("About to try getting and setting the engine's soft memory allocation limit")
	
	limit, usage, err := engine.GetAllocLimit()
	assert(err==nil, "err!!")
	fmt.Printf("engine's initial alloc limit is %dKb (current usage is %dKb)\n", limit, usage)

	limit, usage, err = engine.SetAllocLimit(-1)
	assert(err!=nil, "should have received an err!!")

	limit, usage, err = engine.SetAllocLimit(100)
	assert(err!=nil, "should have received an err!!")

	limit, usage, err = engine.SetAllocLimit(10240)
	assert(err==nil, "err!!")
	fmt.Printf("engine's new alloc limit is %dKb above the current usage of %dKb)\n", limit, usage)

	limit, usage, err = engine.GetAllocLimit()
	assert(err==nil, "err!!")
	fmt.Printf("verified that engine's alloc limit is %dKb (and current usage is %dKb)\n", limit, usage)


	fmt.Println("About to loop through some calls to match (some are designed to fail)")
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
		var input string
		if i%2 == 0 {
			match, err = pat.MatchString("12345")
		} else {
			input = "kjh12345"
			match, err = pat.MatchString(input)
		}
		fmt.Println(match, err)
		if match.Data == nil {
			fmt.Println("Match failed as expected.  Trace is:")
			if trace, err := pat.StrTraceString(input, "full"); err != nil {
				fmt.Printf("err!!  %s\n", err)
			} else {
				fmt.Println(*trace)
			}
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

	limit, usage, err = engine.GetAllocLimit()
	assert(err==nil, "err!!")
	fmt.Printf("checking engine's alloc limit: %dKb, and current usage is %dKb\n", limit, usage)


	// Penultimate test is to import a package that is in the
	// standard library, but which should FAIL TO LOAD because the
	// libpath no longer includes the standard library, due to the
	// call to SetLibpath() above.
	fmt.Println("About to import the 'json' package, which should fail due to a bad loadpath")
	ok, pkgname, msgs, err = engine.ImportPkg("json")
	fmt.Println(ok, pkgname, msgs, err)
	assert(!ok, "import succeeded???")
	assert(len(msgs) != 0, "importing this file should have produced messages")
	assert(err==nil, "err!!")

	// Final test is to load a string that imports 'num', which
	// should succeed because it has already been imported, and
	// the RPL 'import' statement is idempotent.  Contrast to the
	// rosie_import() API, which will re-import the library.
	fmt.Println("About to load 'import num' as an RPL string")
	ok, pkgname, msgs, err = engine.LoadString("import num")
	fmt.Println(ok, pkgname, msgs, err)
	assert(ok, "import failed")
	assert(len(msgs) == 0, "no output was expected")
	assert(err==nil, "err!!")


	// Exit

	fmt.Printf("Exiting... %d errors occurred\n", errs)
	if errs > 0 {
		os.Exit(1)
	}
	os.Exit(0)
}
