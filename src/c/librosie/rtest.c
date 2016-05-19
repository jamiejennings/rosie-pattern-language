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
  lua_State *L = luaL_newstate();
  if (L == NULL) {
    l_message(argv[0], "cannot create lua state: not enough memory");
    exit(-2);
  }

/* 
   luaL_checkversion checks whether the core running the call, the core that created the Lua state,
   and the code making the call are all using the same version of Lua. Also checks whether the core
   running the call and the core that created the Lua state are using the same address space.
*/   
  luaL_checkversion(L);

  luaL_openlibs(L);				    /* open standard libraries */

  initialize(L, QUOTE_EXPAND(ROSIE_HOME));	/* initialize Rosie */

  const char *name = "REPL ENGINE";
  status = rosie_api(L, "new_engine", name, "");    /* leaves engine id on stack */

  const char *eid = lua_tostring(L, 1);
  
  status = rosie_api(L, "get_env", eid, "");	   
  status = rosie_api(L, "configure", eid, "{\"expression\": \"[:digit:]+\", \"encoder\": \"json\"}");
  status = rosie_api(L, "inspect_engine", eid, "");
  status = rosie_api(L, "match", eid, "123");
  status = rosie_api(L, "match", eid, "123 abcdef");
  status = rosie_api(L, "match", eid, "hi");


  lua_getglobal(L, "repl");	  /* push repl fcn */
  lua_pushstring(L, eid);	  /* engine id */
  lua_call(L, 1, 1);		  /* call repl(eid) */

  lua_close(L);
  return (status == LUA_OK) ? EXIT_SUCCESS : EXIT_FAILURE;

}

