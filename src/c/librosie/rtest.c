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

  initialize(QUOTE_EXPAND(ROSIE_HOME));	/* initialize Rosie */

  const char *name = "REPL ENGINE";
  status = rosie_api("new_engine", name, "");    /* leaves engine id on stack */

  lua_State *L = get_L();  
  const char *eid = lua_tostring(L, 1);
  
  status = rosie_api( "get_env", eid, "");	   
  status = rosie_api( "configure", eid, "{\"expression\": \"[:digit:]+\", \"encoder\": \"json\"}");
  status = rosie_api( "inspect_engine", eid, "");
  status = rosie_api( "match", eid, "123");
  status = rosie_api( "match", eid, "123 abcdef");
  status = rosie_api( "match", eid, "hi");


  lua_getglobal(L, "repl");	  /* push repl fcn */
  lua_pushstring(L, eid);	  /* engine id */
  lua_call(L, 1, 1);		  /* call repl(eid) */

  lua_close(L);
  return (status == LUA_OK) ? EXIT_SUCCESS : EXIT_FAILURE;

}

