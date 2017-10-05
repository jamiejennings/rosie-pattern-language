/*  -*- Mode: C/l; -*-                                                       */
/*                                                                           */
/*  librosie.h                                                               */
/*                                                                           */
/*  © Copyright IBM Corporation 2016, 2017.                                  */
/*  LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)  */
/*  AUTHOR: Jamie A. Jennings                                                */

#define INITIAL_RPLX_SLOTS 32
#define INITIAL_ALLOC_LIMIT_MB 0
#define MIN_ALLOC_LIMIT_MB 10

#define TRUE 1
#define FALSE 0

#define SUCCESS 0
#define ERR_OUT_OF_MEMORY -2
#define ERR_SYSCALL_FAILED -3
#define ERR_ENGINE_CALL_FAILED -4

#include <stdint.h>
#include <sys/param.h>		/* MAXPATHLEN */
#include "../../submodules/rosie-lpeg/src/rpeg.h"

typedef struct rosie_string str;

typedef struct rosie_matchresult {
     str data;
     int leftover;
     int ttotal;
     int tmatch;
} match;

str rosie_new_string(byte_ptr msg, size_t len);
str *rosie_new_string_ptr(byte_ptr msg, size_t len);
void rosie_free_string(str s);
void rosie_free_string_ptr(str *s);

void *rosie_new(str *errors);
void rosie_finalize(void *L);
int rosie_set_alloc_limit(lua_State *L, int newlimit);
int rosie_config(lua_State *L, str *retvals);
int rosie_compile(lua_State *L, str *expression, int *pat, str *errors);
int rosie_free_rplx(lua_State *L, int pat);
int rosie_match(lua_State *L, int pat, int start, char *encoder, str *input, match *match);
int rosie_load(lua_State *L, int *ok, str *src, str *pkgname, str *errors);
int rosie_import(lua_State *L, int *ok, str *pkgname, str *as, str *errors);

/*

Administrative:
+  status:int, engine:void* = new(const char *name)
+  status:int = finalize(void *engine)
+  status:int, desc:string = config(void *engine)
  status:int = setlibpath(void *engine, const char *libpath)
+  set soft memory limit to m MB, with optional logging of when it is hit
  logging level (to stderr)?
  clone an engine?  (to avoid setup cost; but cloned engine must be in new Lua state)


RPL:
+  status:int, pkgname:string, errors:strings = load(void *engine, const char *rpl)
+  status:int, pkgname:string, errors:strings = import(packageref, localname)
  status:int = undefine(id)
  test(rpl)?
  testfile(filename)?

Match/trace:
+  status:int, pat:int, errors:strings = compile(void *engine, const char *expression)
+  status:int = free_rplx(void *engine, int pat)
+  status:int = match(void *engine, int pat, int start, str *encoder,
		str *input, match *match);
  status:int, tracestring:*buffer = trace(void *engine, int pat, buffer *input, int start, int encoder, int tracestyle)

  status:int, cin:int, cout:int, cerr:int, errors:strings =
  matchfile(void *engine, int pat, const char *infilename, const char *outfilename, const char *errfilename, int start, int encoder, int wholefile)

  status:int, cin:int, cout:int, cerr:int, errors:strings =
  tracefile(void *engine, void pat, const char *infilename, const char *outfilename, const char *errfilename, int start, int encoder, int readmethod, int tracestyle)

Debugging:
  status:int, desc:string = lookup(void *engine, const char *id)
  status:int, expr:string, errors:strings = expand(void *engine, const char *expr)
  status:int, descs:strings = list(void *engine, const char *localnamefilter, const char *packagenamefilter)


Inventory of functions accessible from Lua:

    > for k,v in pairs(rosie) do print(k,v) end
X    env	table: 0x7fdb744105d0
X    import	function: 0x7fdb74410a80
X    config	function: 0x7fdb74643280
    config_json	function: 0x7fdb7462b630
X    engine	<recordtype: 0x7fdb7684bec0>
X    encoders	table: 0x7fdb7442afa0
X    set_configuration	function: 0x7fdb74700c80

    > for k,v in pairs(rosie.engine) do print(k,v) end
X    is	function: 0x7fdb7444e9e0
M    new	function: 0x7fdb7444e350
X    factory	function: 0x7fdb7444e8f0

    > for k,v in pairs(e) do print(k,v) end
X    name	function: 0x7fdb746b5af0
X    error	function: 0x7fdb7444e3a0
X    id	function: 0x7fdb7441ce70
X    pkgtable	<module_table>
X    compiler	table: 0x7fdb746a3ff0
*    searchpath	/Users/jjennings/Dev/public/rosie-pattern-language/rpl
    compile	function: 0x7fdb7444daf0
    import	function: 0x7fdb7444dc60
    load	function: 0x7fdb7444dc10
    loadfile	function: 0x7fdb7444dcc0
    match	function: 0x7fdb7444de70
    matchfile	function: 0x7fdb7444e270
J    trace	function: 0x7fdb7444dee0
    tracefile	function: 0x7fdb7444e2e0
X    env	<environment: 0x7fdb7684cc30>
    > 

    > for k,v in pairs(e.env) do print(k,v) end
X    bind	function: 0x7fdb74632f00
X    parent	<environment: 0x7fdb76855950>
M    unbind	function: 0x7fdb74632f30
J    lookup	function: 0x7fdb74632ea0
X    bindings	function: 0x7fdb746330b0
X    store	table: 0x7fdb74504ba0
X    exported	false
    > 

*/
