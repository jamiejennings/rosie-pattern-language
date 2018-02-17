//  -*- Mode: Go; -*-                                                 
// 
//  rosie.go
// 
//  © Copyright IBM Corporation 2017, 2018.
//  LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
//  AUTHOR: Jamie A. Jennings

// Package rosie contains functions for using Rosie Pattern Language
package rosie

// #cgo LDFLAGS: ${SRCDIR}/librosie.a -lm -ldl
// #include <stdlib.h>
// #include "librosie.h"
// #cgo CFLAGS: -I./include
import "C"

import "unsafe"
import "errors"
import "runtime"
import "encoding/json"

type Engine struct {
 	ptr *C.struct_rosie_engine
}

type Pattern struct {
	id C.int
	engine *Engine
}

type Match struct {
	Data map[string]interface{}
	Leftover int
	Abend bool
	Total_time int
	Match_time int
}

type (
	Trace map[string]interface{}
	Configuration [] [] map[string] string
	Messages [] interface{}
	RosieString = C.struct_rosie_string
	RosieStringPtr = *C.struct_rosie_string
)

func finalizeEngine(en *Engine) {
	C.rosie_finalize(en.ptr)
}
		
func finalizePattern(p *Pattern) {
	if p.id != 0 {
		C.rosie_free_rplx(p.engine.ptr, p.id)
		p.id = C.int(0)
	}
}


// -----------------------------------------------------------------------------
// String conversions, message decoding

// goString converts a rosie string to a go string
func goString(cstr RosieString) string {
	return C.GoStringN((*C.char)(unsafe.Pointer(cstr.ptr)), C.int(cstr.len))
}

// goBytes converts a rosie string to a go byte slice
func goBytes(cstr RosieString) []byte {
	return C.GoBytes(unsafe.Pointer(cstr.ptr), C.int(cstr.len))
}

// rosieString converts a go string to a rosie string
func rosieString(s string) RosieString {
	return C.rosie_string_from((*C.uchar)(unsafe.Pointer(C.CString(s))), C.size_t(len(s)))
}

// rosieStringFromBytes converts a go byte slice to a rosie string
func rosieStringFromBytes(b []byte) RosieString {
	return C.rosie_string_from((*C.uchar)(C.CBytes(b)), C.size_t(len(b)))
}


func mungeMessages(Cmessages RosieString) (messages Messages, err error) {
	if Cmessages.ptr != nil {
		err := json.Unmarshal(goBytes(Cmessages), &messages)
		if err != nil {
			return nil, err
		}
		return messages, nil
 	} 
	return nil, nil
}


// -----------------------------------------------------------------------------
// Create a rosie pattern engine

func New(name string) (en *Engine, err error) {
	var messages RosieString
	var en_ptr *C.struct_rosie_engine
	en_ptr, err = C.rosie_new(&messages)
	if en_ptr == nil {
		var printable_message string
		if messages.ptr == nil {
			printable_message = "initialization failed with an unknown error"
		} else {
			printable_message = goString(messages)
		}
		return nil, errors.New(printable_message)
	}
	engine := Engine{en_ptr}
	runtime.SetFinalizer(&engine, finalizeEngine)
	return &engine, nil
}


// -----------------------------------------------------------------------------
// Get an engine's configuration

func (en *Engine) Config() (cfg Configuration, err error) {
	var data C.struct_rosie_string
	defer C.rosie_free_string(data)
 	if ok, err := C.rosie_config(en.ptr, &data); ok != 0 {
		return nil, err
	}
	if err = json.Unmarshal(goBytes(data), &cfg); err != nil {
		return nil, err
	}
	return cfg, err
}


// -----------------------------------------------------------------------------
// Compile an expression, returning a compiled pattern

func (en *Engine) Compile(exp string) (pat *Pattern, messages Messages, err error) {
 	var Cexp = rosieString(exp)
	var Cmessages RosieString
	pat = &Pattern{C.int(0), en}
	runtime.SetFinalizer(pat, finalizePattern)
	defer C.rosie_free_string(Cmessages)
	
 	if ok, err := C.rosie_compile(en.ptr, &Cexp, &pat.id, &Cmessages); ok != 0 {
		return pat, nil, err
	}
	if messages, err = mungeMessages(Cmessages); err != nil {
		pat = nil
	}
	return pat, messages, err
}


// -----------------------------------------------------------------------------
// Match an input string or byte slice against a compiled pattern

func (pat *Pattern) Match(input []byte) (match *Match, err error) {
	return pat.MatchFrom(input, 1)
}
	
func (pat *Pattern) MatchString(input string) (match *Match, err error) {
	return pat.MatchStringFrom(input, 1)
}
	
func (pat *Pattern) MatchStringFrom(input string, start int) (match *Match, err error) {
	return pat.MatchFrom([]byte(input), start)
}

func (pat *Pattern) MatchFrom(input []byte, start int) (match *Match, err error) {
	var Cmatch C.struct_rosie_matchresult
	var Cinput = rosieStringFromBytes(input)
	defer C.rosie_free_string(Cinput)
	var Cencoder = C.CString("json")
	var newMatch Match
	match = &newMatch
	
	ok, err := C.rosie_match(pat.engine.ptr, pat.id, C.int(start), Cencoder, &Cinput, &Cmatch)
	if ok != 0 {
		return nil, err
	}

 	match.Leftover = int(Cmatch.leftover)
 	match.Abend = (Cmatch.abend != 0)
 	match.Total_time = int(Cmatch.ttotal)
 	match.Match_time = int(Cmatch.tmatch)

	if Cmatch.data.ptr != nil {
		if err = json.Unmarshal(goBytes(Cmatch.data), &match.Data); err != nil {
			return nil, err
		}
	}

	return match, nil
}

// -----------------------------------------------------------------------------
// TODO: Match with choice of output encoder, returning match data as
// byte slice or string



// -----------------------------------------------------------------------------
// TODO: Trace without choice of output encoder, returning a map of
// the full trace


// -----------------------------------------------------------------------------
// Trace the matching process, given an input string or byte slice and
// a compiled pattern

func (pat *Pattern) StrTrace(input []byte, style string) (trace *string, err error) {
	return pat.StrTraceFrom(input, 1, style)
}
	
func (pat *Pattern) StrTraceString(input string, style string) (trace *string, err error) {
	return pat.StrTraceStringFrom(input, 1, style)
}
	
func (pat *Pattern) StrTraceStringFrom(input string, start int, style string) (trace *string, err error) {
	return pat.StrTraceFrom([]byte(input), start, style)
}

func (pat *Pattern) StrTraceFrom(input []byte, start int, style string) (trace *string, err error) {
	var Ctrace RosieString
	var Cinput = rosieStringFromBytes(input)
	defer C.rosie_free_string(Cinput)
	var Cstyle = C.CString(style)
	var Cmatch_flag = C.int(0)
	
	ok, err := C.rosie_trace(pat.engine.ptr, pat.id, C.int(start), Cstyle, &Cinput, &Cmatch_flag, &Ctrace)
	if ok != 0 {
		return nil, err
	}

	if Ctrace.ptr == nil {
		// Error occurred (but not a bug)
		switch Ctrace.len {
		case 2: return nil, errors.New("invalid trace style")
		case 1: return nil, errors.New("invalid compiled pattern (already freed?)")
		default: return nil, errors.New("unknown error during trace")
		}
	}

	answer := goString(Ctrace)
	return &answer, nil

}

// -----------------------------------------------------------------------------
// Load RPL code into a Rosie engine

func (en *Engine) LoadString(src string) (ok bool, pkgname string, messages Messages, err error) {
	var Cok = C.int(0)
 	var Csrc = rosieString(src)
	var Cmessages, Cpkgname RosieString
	defer C.rosie_free_string(Cmessages)
	
 	loadOK, errLoad := C.rosie_load(en.ptr, &Cok, &Csrc, &Cpkgname, &Cmessages)
	messages, err = mungeMessages(Cmessages)
	pkgname = goString(Cpkgname)
	if loadOK != 0 {
		return false, pkgname, messages, errLoad
	}
	return (Cok==1), pkgname, messages, nil
}

func (en *Engine) LoadFile(fn string) (ok bool, pkgname string, messages Messages, err error) {
	var Cok = C.int(0)
 	var Cfn = rosieString(fn)
	var Cmessages, Cpkgname RosieString
	defer C.rosie_free_string(Cmessages)
	
 	loadOK, errLoad := C.rosie_loadfile(en.ptr, &Cok, &Cfn, &Cpkgname, &Cmessages)
	messages, err = mungeMessages(Cmessages)
	pkgname = goString(Cpkgname)
	if loadOK != 0 {
		return false, pkgname, messages, errLoad
	}
	return (Cok==1), pkgname, messages, nil
}

func (en *Engine) ImportPkg(pkgname string) (bool, string, Messages, error) {
	return en.ImportPkgAs(pkgname, "")
}

func (en *Engine) ImportPkgAs(pkgname string, asname string) (ok bool, actualPkgname string, messages Messages, err error) {
	var Cok = C.int(0)
 	var Cpkgname = rosieString(pkgname)
	var CactualPkgname = C.rosie_string_from(nil, 0)
 	var Casname RosieString
	var Casname_ptr RosieStringPtr = nil
	if asname != "" {
		Casname = rosieString(asname)
		Casname_ptr = &Casname
	}
	var Cmessages RosieString
	defer C.rosie_free_string(Cmessages)
	
 	loadOK, errLoad := C.rosie_import(en.ptr, &Cok, &Cpkgname, Casname_ptr, &CactualPkgname, &Cmessages)
	messages, err = mungeMessages(Cmessages)
	actualPkgname = goString(CactualPkgname)
	if loadOK != 0 {
		return false, actualPkgname, messages, errLoad
	}
	return (Cok==1), actualPkgname, messages, nil
}

// -----------------------------------------------------------------------------
// Get, set the engine's search path (a colon-separated list of
// directories to search for libraries loaded via 'import'.

func (en *Engine) GetLibpath() (libpath string, err error) {
	var Clibpath = C.rosie_string_from(nil, 0)
 	if ok, err := C.rosie_libpath(en.ptr, &Clibpath); ok != 0 {
		return "", err
	}
	libpath = goString(Clibpath)
	return libpath, nil
}

func (en *Engine) SetLibpath(libpath string) (err error) {
	var Clibpath = rosieString(libpath)
 	if ok, err := C.rosie_libpath(en.ptr, &Clibpath); ok != 0 {
		return err
	}
	return nil
}

// -----------------------------------------------------------------------------
// Get, set the engine's memory allocation limit, which is a number of
// Kb above whatever is the current memory usage level.  When Rosie's
// working memory (heap) exceeds the soft limit, it will force a GC in
// a best effort to reduce memory consumption.

func (en *Engine) GetAllocLimit() (softlimit int, current_usage int, err error) {
	var Climit = C.int(-1)
	var Cusage = C.int(0)
 	if ok, err := C.rosie_alloc_limit(en.ptr, &Climit, &Cusage); ok != 0 {
		return 0, 0, err
	}
	return int(Climit), int(Cusage), nil
}

func (en *Engine) SetAllocLimit(softlimit int) (actual_limit int, current_usage int, err error) {
	if (softlimit < 8192) && (softlimit != 0) {
		return 0, 0, errors.New("limit must be 0 or higher than the Rosie minimum value")
	}
	var Climit = C.int(softlimit)
	var Cusage = C.int(0)
 	if ok, err := C.rosie_alloc_limit(en.ptr, &Climit, &Cusage); ok != 0 {
		return 0, 0, err
	}
	return int(Climit), int(Cusage), nil
}






