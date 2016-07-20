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

  struct string_array array = testretarray(CONST_STRING("Hello, world!"));
  printf("Array length is: %d\n", array.n);
  for (uint32_t i=0; i < array.n; i++) {
       struct string *cstr = array.ptr[i];
       printf("\t %d: len=%d, string=%s\n", i, cstr->len, cstr->ptr);
  }

  printf("\n");

  struct string_array2 array2 = testretarray2(CONST_STRING("Hello, world!"));
  printf("Array length is: %d\n", array2.n);
  struct string **cstr_ptr = array.ptr; 
  for (uint32_t i=0; i < array2.n; i++) { 
       struct string c = *(cstr_ptr[i]);
       printf("\t %d: len=%d, string=%s\n", i, c.len, c.ptr); 
  } 

  printf("\n");
  

  initialize(QUOTE_EXPAND(ROSIE_HOME));	/* initialize Rosie */

  lua_State *L = get_L();   

  struct string eid_string_encoded;
  struct string *initial_config = &CONST_STRING("{\"name\":\"A NEW ENGINE\"}");
  eid_string_encoded = new_engine(initial_config);
  
  /* Now json.decode the result */

  lua_getglobal(L, "json");
  lua_getfield(L, -1, "decode");
  lua_remove(L, -2);		/* remove json from stack */
  lua_pushlstring(L, (char *)eid_string_encoded.ptr, (size_t) eid_string_encoded.len);

  /* For valgrind to not complain: */
  free_string(eid_string_encoded);

  lua_call(L, 1, 1);		/* call json.decode */
  lua_geti(L, -1, 1);		/* get 1st element of table */

  if (lua_isboolean(L, -1) != TRUE) {
       l_message("rtest", lua_pushfstring(L, "librosie error: first return value of new_engine not a boolean"));
       exit(-1);
  }

  if (lua_toboolean(L, -1) != TRUE) {
       lua_pop(L, 1);	    /* remove 1st element, the success code */
       lua_geti(L, -1, 2);  /* get 2nd element of table, the error message */
       /* TEMPORARY */
       l_message("rtest", lua_tostring(L, 1));
       exit(-1);
  }

  lua_pop(L, 1);      /* remove 1st element, the success code */
  lua_geti(L, -1, 2); /* get 2nd element of table, the eid id (string) */

  size_t len;
  uint8_t *src = (uint8_t *)lua_tolstring(L, -1, &len);
  struct string eid_string = { len, src };
  
  lua_pop(L, 2);		/* remove decoded string, table */ 

  printf("eid_string: len=%d string=%s\n", eid_string.len, (char *)eid_string.ptr);

  static struct string null = CONST_STRING("null");

  struct string r = rosie_api( "get_environment", &eid_string, &null);	   
  printf("result of get_environment: len=%d string=%s\n", r.len, (char *)r.ptr);
  free_string(r);

  struct string *arg = &(CONST_STRING("{\"expression\": \"[:digit:]+\", \"encode\": \"json\"}"));

  r = rosie_api( "configure_engine", &eid_string, arg); 
  printf("result of configure_engine: len=%d string=%s\n", r.len, (char *)r.ptr);
  free_string(r);

  r = rosie_api( "inspect_engine", &eid_string, &null); 
  printf("result of inspect_engine: len=%d string=%s\n", r.len, (char *)r.ptr);
  free_string(r);

  arg = &CONST_STRING("123");
  r = rosie_api( "match", &eid_string, arg); 
  printf("result of match: len=%d string=%s\n", r.len, (char *)r.ptr);
  free_string(r);

  arg = &CONST_STRING("123 abcdef");
  r = rosie_api( "match", &eid_string, arg); 
  printf("result of match: len=%d string=%s\n", r.len, (char *)r.ptr);
  free_string(r);

  arg = &CONST_STRING("hi");
  r = rosie_api( "match", &eid_string, arg); 
  printf("result of match: len=%d string=%s\n", r.len, (char *)r.ptr);
  free_string(r);

  lua_getglobal(L, "repl");	/* push repl fcn */
  lua_getglobal(L, "engine_list");
  lua_pushlstring(L, (char *)eid_string.ptr, eid_string.len);
  lua_gettable(L, -2);
  /* top of stack is now enginelist[eid_string] */
  lua_remove(L, -2);		/* remove engine_list from stack */
  lua_call(L, 1, 1);		/* call repl(eid) */

  lua_close(L);

  return EXIT_SUCCESS;

}

