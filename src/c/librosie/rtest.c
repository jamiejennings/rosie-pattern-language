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

/* struct string utf8_to_printable(string src) { */
/*      struct string dst; */
/*      dest.ptr = malloc(sizeof(char)*4*src.len+1); */
/*      unsigned int d_ptr = dest.ptr */
/*      for (unsigned int i=1; i<=src.len; i++) { */
/* 	  if ( *(src.ptr+i)==0 ) { */
/* 	       memcpy(dest.ptr,  */
/* } */
     

     

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
  
  /* Now json.decode the result */

  lua_getglobal(L, "json");
  lua_getfield(L, -1, "decode");
  lua_remove(L, -2);		/* remove json from stack */
  lua_pushlstring(L, (char *)foo.ptr, (size_t) foo.len);

  lua_call(L, 1, 1);		/* call json.decode */
  lua_geti(L, -1, 1);		/* get 1st element of table */

/* NEED TO CHANGE ALL USES OF strlcpy, WHICH ASSUMES NULL-TERMINATED STRINGS */

  size_t len;
  uint8_t *src = (uint8_t *)lua_tolstring(L, -1, &len);
  uint8_t *eid = malloc(sizeof(uint8_t)*(len+1));
  /* if (len > MAX_ENGINE_ID_LEN) luaL_error(L, "error: MAX_ENGINE_ID_LEN too small"); */
  memcpy(eid, src, len);
  eid[len+1] = 0;
  struct string eid_string = { len, eid };

  lua_pop(L, 2);		/* remove decoded string, table */ 

  printf("eid_string: len=%d string=%s\n", eid_string.len, (char *)eid_string.ptr);

  static struct string null = { strlen("null"), (uint8_t *)"null" };

#define CONFIG ("{\"expression\": \"[:digit:]+\", \"encode\": \"json\"}")
  struct string arg = { strlen(CONFIG), (uint8_t *)CONFIG };

  status = rosie_api( "get_environment", eid_string, null);	   

  status = rosie_api( "configure_engine", eid_string, arg); 
  status = rosie_api( "inspect_engine", eid_string, null); 

  arg = (struct string) {strlen("123"), (uint8_t *)"123"};
  status = rosie_api( "match", eid_string, arg); 

  arg = (struct string) {strlen("123 abcdef"), (uint8_t *)"123 abcdef"};
  status = rosie_api( "match", eid_string, arg); 

  arg = (struct string) {strlen("hi"), (uint8_t *)"hi"};
  status = rosie_api( "match", eid_string, arg); 


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

