/*  -*- Mode: C; -*-                                                         */
/*                                                                           */
/* librosie.c    Expose the Rosie API                                        */
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

/* For now, we are only supporting one Lua state.  This is NOT thread-safe. */
static lua_State *LL = NULL;
static const char *progname = "librosie";

void print_error_message (const char *msg) {
     lua_writestringerror("%s: ", progname);
     lua_writestringerror("%s\n", msg);
}

static void stackDump (lua_State *L) {
      int i;
      int top = lua_gettop(L);
      if (top==0) { printf("EMPTY STACK\n"); return;}
      for (i = top; i >= 1; i--) {
        int t = lua_type(L, i);
        switch (t) {
    
          case LUA_TSTRING:  /* strings */
	       printf("%d: '%s'", i, lua_tostring(L, i));
            break;
    
          case LUA_TBOOLEAN:  /* booleans */
	       printf("%d: %s", i, (lua_toboolean(L, i) ? "true" : "false"));
            break;
    
          case LUA_TNUMBER:  /* numbers */
	       printf("%d: %g", i, lua_tonumber(L, i));
            break;
    
          default:  /* other values */
	       printf("%d: %s", i, lua_typename(L, t));
            break;
    
        }
        printf("  ");  /* put a separator */
      }
      printf("\n");  /* end the listing */
    }

#define QUOTE_EXPAND(name) QUOTE(name)		    /* expand name */
#define QUOTE(thing) #thing			    /* stringify it */

int bootstrap (const char *rosie_home) {
     char name[MAXPATHSIZE + 1];
     if (strlcpy(name, rosie_home, sizeof(name)) >= sizeof(name))
	  luaL_error(LL, "error during bootstrap: MAXPATHSIZE too small");
     if (strlcat(name, "/src/bootstrap.lua", sizeof(name)) >= sizeof(name))
	  luaL_error(LL, "error during bootstrap: MAXPATHSIZE too small");
     return luaL_dofile(LL, name);
}

void require (const char *name, int assign_name) {  
     int status;  
     lua_getglobal(LL, "require");  
     lua_pushstring(LL, name);  
     status = lua_pcall(LL, 1, 1, 0);                   /* call 'require(name)' */  
     if (status != LUA_OK) {  
	  print_error_message(lua_pushfstring(LL, "Internal error: cannot load %s (%s)", name, lua_tostring(LL, -1)));  
	  exit(-1);  
     }  
     if (assign_name==TRUE) lua_setglobal(LL, name); /* set the global to the return value of 'require' */  
     else lua_pop(LL, 1);    /* else discard the result of require */  
}  

int initialize(const char *rosie_home) {
     int status;
     lua_State *L = luaL_newstate();
     if (L == NULL) {
	  print_error_message("error during initialization: not enough memory");
	  exit(-2);
     }
     LL = L;
/* 
   luaL_checkversion checks whether the core running the call, the core that created the Lua state,
   and the code making the call are all using the same version of Lua. Also checks whether the core
   running the call and the core that created the Lua state are using the same address space.
*/   
  luaL_checkversion(L);
  luaL_openlibs(L);
  lua_pushstring(L, rosie_home);
  lua_setglobal(L, "ROSIE_HOME");
  LOGf("Initializing Rosie, where ROSIE_HOME = %s\n", rosie_home);
  status = bootstrap(rosie_home);
  if (status != LUA_OK) return (-1); 
  require("api", TRUE);
  return 0;
}

struct string *heap_allocate_string(const char *msg) {
     size_t len = (size_t) strlen(msg);
     uint8_t *ptr = malloc(len+1);     /* to return a string, we must make */
     strlcpy((char *)ptr, msg, len+1); /* sure it is allocated on the heap */
     struct string *retval = malloc(sizeof(struct string));
     retval->len = len;
     retval->ptr = ptr;
     return retval;
}     

struct stringArray testretarray(struct string foo) {
     printf("testretarray argument received: len=%d, string=%s\n", foo.len, foo.ptr);

     struct string *b = heap_allocate_string("This is a new struct string called b.");
     struct string *c = heap_allocate_string("This is a new struct string called c.");
     struct string *d = heap_allocate_string("This is a new struct string called d.");
     struct string **ptr = malloc(sizeof(struct string *) * 3);
     ptr[0] = b; ptr[1] = c; ptr[2] = d;

     return (struct stringArray) {3, ptr};

}

struct string *copy_string_ptr(struct string *src) {
     struct string *dest = malloc(sizeof(struct string));
     dest->len = src->len;
     dest->ptr = malloc(sizeof(uint8_t)*src->len);
     memcpy(dest->ptr, src->ptr, src->len);
     return dest;
}

void free_string_ptr(struct string *ref) {
     free(ref->ptr);
     free(ref);
}

void free_string(struct string s) {
     free(s.ptr);
}

void free_stringArray(struct stringArray r) {
     struct string **s = r.ptr;
     for (uint32_t i=0; i<r.n; i++) {
	  free(s[i]->ptr);
	  free(s[i]);
     }
     free(r.ptr);
}

struct stringArray rosie_api(const char *name, ...) {

     lua_State *L = LL;
     va_list args;
     struct string *arg;

     /* number of args AFTER the api name */
     int nargs = 2;		   /* get this later from a table */

     va_start(args, name);	   /* setup variadic arg processing */
     LOGf("Stack at start of rosie_api (%s):\n", name);
     LOGstack(L);

     /* Optimize later: memoize stack value of fcn for each api call to avoid this lookup? */
     lua_getglobal(L, "api");
     lua_getfield(L, -1 , name);                    /* -1 is stack top, i.e. api table */
     lua_remove(L, -2);	    /* remove the api table from the stack */ 
     for (int i = 1; i <= nargs; i++) {
	  arg = va_arg(args, struct string *); /* get the next arg */
	  lua_pushlstring(L, (char *) arg->ptr, arg->len); /* push it */
     }
     va_end(args);

     LOGf("About to call the api the function on the stack, and nargs=%d\n", nargs);  
     LOGstack(L);  
     /* API CALL */
     lua_call(L, nargs, 1); 
     LOG("Stack immediately after lua_call:\n");
     LOGstack(L);
     
     if (lua_istable(L, -1) != TRUE) {
	  print_error_message(lua_pushfstring(L, "librosie internal error: return value of %s not a table", name));
	  exit(-1);
     }

     struct stringArray retvals;
     size_t nretvals = lua_rawlen(L, -1);
     struct string **list = malloc(sizeof(struct string *) * nretvals);
     size_t len;
	  
     for (size_t i=0; i<nretvals; i++) {
	  int t = lua_rawgeti(L, -1, (lua_Integer) i+1);    /* lua has 1-based indexing */
	  list[i] = malloc(sizeof(struct string));
	  char *str;
	  switch (t) {
	  case LUA_TSTRING:
	       str = (char *) lua_tolstring(L, -1, &len);
	       break;
	  case LUA_TBOOLEAN:
	       if (lua_toboolean(L, -1)) {len=4; str="true";}
	       else {len=5; str="false";}
	       break;
	  default:
	       LOGf("Return type error: %d\n", t);
	       len=0; str = "";
	  }
	  LOGf("Return value [%d]: len=%d ptr=%s\n", (int) i, (int) len, str);
	  list[i]->len = len;
	  list[i]->ptr = malloc(sizeof(uint8_t)*(len+1));
	  memcpy(list[i]->ptr, str, len);
	  list[i]->ptr[len] = 0; /* so we can use printf for debugging */	  
	  LOGf("  Encoded as struct string: len=%d ptr=%s\n", (int) list[i]->len, list[i]->ptr);
	  lua_pop(L, 1);
     }
     retvals.n = nretvals;
     retvals.ptr = list;

     lua_pop(L, 1);		/* pop the api call's results table */

     LOGf("Stack at end of call to Rosie api: %s\n", name); 
     LOGstack(L); 
     
     return retvals;
}


struct stringArray new_engine(struct string *config) {

     struct string *ignore = &CONST_STRING("ignored");
     struct stringArray retvals = rosie_api("new_engine", config, ignore);
     LOGf("In new_engine, number of retvals from rosie_api was %d\n", retvals.n);
     if (retvals.n !=2) {
	  print_error_message(lua_pushfstring(LL,
				    "librosie internal error: wrong number of return values to new_engine (%d)",
				    retvals.n));
	  exit(-1);
     }
     struct string *code = stringArrayRef(retvals, 0);
     char *true_value = "true";
     if (memcmp(code->ptr, true_value, (size_t) code->len)) {
	  LOGf("Success code was NOT true: len=%d, ptr=%s\n", code->len, code->ptr);
	  struct string *err = stringArrayRef(retvals,1);
	  LOGf("Error in new_engine: %s\n", (char *) err->ptr);
     }
     return retvals;
}


void delete_engine(struct string *eid_string) {
     struct string *ignore = &CONST_STRING("ignored12345");
     struct stringArray retvals = rosie_api("delete_engine", eid_string, ignore);
     LOGf("In new_engine, number of retvals from delete_engine was %d\n", retvals.n);
     free_stringArray(retvals);
}

void finalize() {
     lua_close(LL);
}
