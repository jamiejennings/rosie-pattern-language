/*  -*- Mode: C/l; -*-                                                       */
/*                                                                           */
/* rosie.c      Create a Lua state, load Rosie, expose the Rosie API         */
/*                                                                           */
/*  © Copyright IBM Corporation 2016.                                        */
/*  LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)  */
/*  AUTHOR: Jamie A. Jennings                                                */


/* ROSIE_HOME defined on the command line during compilation (see Makefile)  */

#ifndef ROSIE_HOME
#error "ROSIE_HOME not defined.  Check CFLAGS in Makefile?"
#endif

#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>

#include "lauxlib.h"
#include "lualib.h"

#include "librosie.h"

#define PROGNAME		"rosie"

/*
---------------------------------------------------------------------------------------------------
 main 
--------------------------------------------------------------------------------------------------- 
*/

#define QUOTE_EXPAND(name) QUOTE(name)		    /* expand name */
#define QUOTE(thing) #thing			    /* stringify it */

int main (int argc, char **argv) {
  int status;

  testbyvalue(CONST_STRING("Hello, world!"));
  struct string foo;
  foo.ptr = (uint8_t *) "This is a test.";
  foo.len = strlen((const char *)foo.ptr);
  testbyref(&foo);
  printf("\n");

  initialize(QUOTE_EXPAND(ROSIE_HOME));	/* initialize Rosie */

  lua_State *L = get_L();   

  struct string eid_string_encoded;
  struct string initial_config = CONST_STRING("{\"name\":\"A NEW ENGINE\"}");
  status = new_engine(&eid_string_encoded, &initial_config);
  
  /* Now json.decode the result */

  lua_getglobal(L, "json");
  lua_getfield(L, -1, "decode");
  lua_remove(L, -2);		/* remove json from stack */
  lua_pushlstring(L, (char *)eid_string_encoded.ptr, (size_t) eid_string_encoded.len);

  /* For valgrind to not complain: */
  FREE_STRING(eid_string_encoded);

  lua_call(L, 1, 1);		/* call json.decode */
  lua_geti(L, -1, 1);		/* get 1st element of table */

  size_t len;
  uint8_t *src = (uint8_t *)lua_tolstring(L, -1, &len);
  struct string eid_string = { len, src };
  
  lua_pop(L, 2);		/* remove decoded string, table */ 

  printf("eid_string: len=%d string=%s\n", eid_string.len, (char *)eid_string.ptr);

  static struct string null = CONST_STRING("null");

  status = rosie_api( "get_environment", &eid_string, &null);	   

  struct string *arg = &(CONST_STRING("{\"expression\": \"[:digit:]+\", \"encode\": \"json\"}"));

  status = rosie_api( "configure_engine", &eid_string, arg); 
  status = rosie_api( "inspect_engine", &eid_string, &null); 

  arg = &CONST_STRING("123");
  status = rosie_api( "match", &eid_string, arg); 

  arg = &CONST_STRING("123 abcdef");
  status = rosie_api( "match", &eid_string, arg); 

  arg = &CONST_STRING("hi");
  status = rosie_api( "match", &eid_string, arg); 

  lua_getglobal(L, "repl");	/* push repl fcn */
  lua_getglobal(L, "engine_list");
  lua_pushlstring(L, (char *)eid_string.ptr, eid_string.len);
  lua_gettable(L, -2);
  /* top of stack is now enginelist[eid_string] */
  lua_remove(L, -2);		/* remove engine_list from stack */
  lua_call(L, 1, 1);		/* call repl(eid) */

  lua_close(L);

  return (status == LUA_OK) ? EXIT_SUCCESS : EXIT_FAILURE;

}

