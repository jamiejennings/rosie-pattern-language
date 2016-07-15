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

#define MAX_ENGINE_ID_LEN 20

int main (int argc, char **argv) {
  int status;
  char eid[MAX_ENGINE_ID_LEN+1];
  
  initialize(QUOTE_EXPAND(ROSIE_HOME));	/* initialize Rosie */

  lua_State *L = get_L();   

  /* const char *config = "{\"name\":\"REPL ENGINE\"}"; */
  /* status = rosie_api("new_engine", config);    /\* leaves engine id on stack *\/ */

  /* const char *eid_js = lua_tostring(L, 1); */
  
  /* lua_getglobal(L, "json"); */
  /* lua_getfield(L, -1, "decode"); */
  /* lua_remove(L, -2);		/\* remove json from stack *\/ */
  /* lua_pushstring(L, eid_js); */
  /* lua_call(L, 1, 1);		/\* call json.decode *\/ */
  /* lua_geti(L, -1, 1);		/\* get 1st element of table *\/ */
  /* if (strlcpy(eid, lua_tostring(L, -1), sizeof(eid)) >= sizeof(eid)) */
  /* 	  luaL_error(L, "error: MAX_ENGINE_ID_LEN too small"); */
  /* lua_pop(L, 3);		/\* remove decoded string, table, decode fcn *\/ */
  
  struct string foo;

  status = new_engine(&foo);
  printf("result of new_engine: len=%d, string=%s\n", foo.len, foo.ptr);

  strlcpy(eid, foo.ptr, sizeof(eid));
  
  status = rosie_api( "get_environment", eid, "null");	   
  status = rosie_api( "configure_engine", eid, "{\"expression\": \"[:digit:]+\", \"encode\": \"json\"}");
  status = rosie_api( "inspect_engine", eid, "");
  status = rosie_api( "match", eid, "123");
  status = rosie_api( "match", eid, "123 abcdef");
  status = rosie_api( "match", eid, "hi");


  lua_getglobal(L, "repl");	/* push repl fcn */
  lua_getglobal(L, "engine_list");
  lua_getfield(L, -1, eid);	/* engine id */
  lua_remove(L, -2);		/* remove engine_list from stack */
  lua_call(L, 1, 1);		/* call repl(eid) */

  lua_close(L);
  return (status == LUA_OK) ? EXIT_SUCCESS : EXIT_FAILURE;

}

