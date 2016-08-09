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

#define EXIT_JSON_DECODE_ERROR -1
#define EXIT_JSON_ENCODE_ERROR -2
#define EXIT_OUT_OF_MEMORY -3

#define new_TRUE_string() (new_string("true", 4))
#define new_FALSE_string() (new_string("false", 5))

/* To do:
   - One Lua state per engine
   - Have initialize create a table of Rosie api functions (store in Lua Registry) 
   - Check result of each malloc, and error out appropriately
   - Put debugging functions like stackDump inside #if DEBUG==1
   - Move json_decode and similar test functions to rtest

*/
/* For now, we are only supporting one Lua state.  This is NOT thread-safe. */
static lua_State *LL = NULL;


/* ----------------------------------------------------------------------------------------
 * Utility functions
 * ----------------------------------------------------------------------------------------
 */

#define QUOTE_EXPAND(name) QUOTE(name)		    /* expand name */
#define QUOTE(thing) #thing			    /* stringify it */

int bootstrap (const char *rosie_home) {
     char name[MAXPATHSIZE + 1];
     if (strlcpy(name, rosie_home, sizeof(name)) < sizeof(name)) {
	  if (strlcat(name, "/src/bootstrap.lua", sizeof(name)) < sizeof(name))
	       return (luaL_dofile(LL, name) == LUA_OK);
     }
     lua_pushstring(LL, "librosie: error during bootstrap: MAXPATHSIZE too small");
     return FALSE;
}

int require (const char *name, int assign_name) {  
     int status;  
     lua_getglobal(LL, "require");  
     lua_pushstring(LL, name);  
     status = lua_pcall(LL, 1, 1, 0);                   /* call 'require(name)' */  
     if (status != LUA_OK) {
	  lua_pop(LL, 1);	/* discard error because the details don't matter */
	  return FALSE;
     }
     if (assign_name==TRUE) lua_setglobal(LL, name); /* set the global to the return value of 'require' */  
     else lua_pop(LL, 1);   /* else discard the result of require */  
     return TRUE;
}  

/* ----------------------------------------------------------------------------------------
 * Debug functions
 * ----------------------------------------------------------------------------------------
 */

static const char *progname = "librosie";

static void print_error_message (const char *msg) {
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

static void print_stringArray(struct stringArray sa, char *caller_name) {
     printf("Values returned in stringArray from: %s\n", caller_name);
     printf("  Number of strings: %d\n", sa.n);
     for (uint32_t i=0; i<sa.n; i++) {
	  struct string *cstrptr = sa.ptr[i];
	  printf("  [%d] len = %d, ptr = %s\n", i, cstrptr->len, cstrptr->ptr);
     }
}


/* ---------------------------------------------------------------------------------------- */
/* MISC STUFF TO RE-DO: */

#if FALSE
struct stringArray json_decode(struct string *js_string) {
     lua_getglobal(LL, "json");
     lua_getfield(LL, -1, "decode");
     LOGf("Fetched json.decode, and top of stack is a %s\n", lua_typename(LL, lua_type(LL, -1)));
     lua_pushlstring(LL, (char *) js_string->ptr, js_string->len);
     LOG("About to call json.decode\n");
     LOGstack(LL);
     int status = lua_pcall(LL, 1, 1, 0);                   /* call 'json.decode(js_string)' */  
     if (status != LUA_OK) {  
	  print_error_message(lua_pushfstring(LL, "Internal error: cannot json.decode %s (%s)", js_string->ptr, lua_tostring(LL, -1)));  
	  exit(EXIT_JSON_DECODE_ERROR);  
     }  
     LOG("After call to json.decode\n");
     LOGstack(LL);

     /* Since we can't return a lua table to C, we will encode it again and return that */
     lua_getfield(LL, -2, "encode");
     LOGf("Fetched json.encode, and top of stack is a %s\n", lua_typename(LL, lua_type(LL, -1)));
     lua_insert(LL, -2);	/* move the table produced by decode to the top */
     LOG("About to call json.encode\n");
     LOGstack(LL);
     status = lua_pcall(LL, 1, 1, 0);                   /* call 'json.encode(table)' */  
     if (status != LUA_OK) {  
	  print_error_message(lua_pushfstring(LL, "Internal error: json.encode failed (%s)", js_string->ptr, lua_tostring(LL, -1)));  
	  exit(EXIT_JSON_ENCODE_ERROR);  
     }  
     LOG("After call to json.encode\n");
     LOGstack(LL);

     uint32_t nretvals = 2;
     struct string **list = malloc(sizeof(struct string *) * nretvals);
     size_t len;
     char *str;
     if (TRUE) {len=4; str="true";}
     else {len=5; str="false";}
     LOGf("len=%d, str=%s", (int) len, (char *)str);
     list[0] = malloc(sizeof(struct string));
     list[0]->len = len;
     list[0]->ptr = malloc(sizeof(uint8_t)*(len+1));
     memcpy(list[0]->ptr, str, len);
     list[0]->ptr[len] = 0; /* so we can use printf for debugging */	  
     LOGf("  Encoded as struct string: len=%d ptr=%s\n", (int) list[0]->len, list[0]->ptr);

     str = (char *) lua_tolstring(LL, -1, &len);
     list[1] = malloc(sizeof(struct string));
     list[1]->len = len;
     list[1]->ptr = malloc(sizeof(uint8_t)*(len+1));
     memcpy(list[1]->ptr, str, len);
     list[1]->ptr[len] = 0; /* so we can use printf for debugging */	  
     LOGf("  Encoded as struct string: len=%d ptr=%s\n", (int) list[1]->len, list[1]->ptr);

     lua_pop(LL, 2);    /* discard the result string and the json table */  
     return (struct stringArray) {2, list};

}  
     
//struct stringArray json_encode(struct string *plain_string);

#endif

/* ----------------------------------------------------------------------------------------
 * Exported functions
 * ----------------------------------------------------------------------------------------
 */

struct stringArray initialize(const char *rosie_home) {

     lua_State *L = luaL_newstate();
     if (L == NULL) {
	  print_error_message("error during initialization: not enough memory");
	  exit(EXIT_OUT_OF_MEMORY);
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
  if (bootstrap(rosie_home)) {
       if (require("api", TRUE)) { 
	    struct string **list = malloc(sizeof(struct string *) * 1);
	    list[0] = new_TRUE_string();
	    /* TODO: return an id here */
	    return (struct stringArray) {1, list};
       }
       else {
	    struct string **list = malloc(sizeof(struct string *) * 2);
	    list[0] = new_FALSE_string();
	    char *str_ptr;
	    int n = asprintf(&str_ptr, "Internal error: cannot load api (%s)", lua_tostring(LL, -1));
	    if (n < 0) exit(EXIT_OUT_OF_MEMORY);  
	    list[1] = malloc(sizeof(struct string));
	    list[1]->ptr = (byte_ptr) str_ptr;
	    list[1]->len = n;
	    lua_close(L);
	    return (struct stringArray) {2, list};
       }
  }
  struct string **list = malloc(sizeof(struct string *) * 2);
  list[0] = new_FALSE_string();
  list[1] = malloc(sizeof(struct string));
  byte_ptr str = (byte_ptr) lua_tolstring(LL, -1, (size_t *) &(list[1]->len));
  memcpy(list[1]->ptr, str, list[1]->len);
  lua_close(L);
  return (struct stringArray) {2, list};
}

struct string *new_string(char *msg, size_t len) {
     byte_ptr ptr = malloc(len+1);     /* to return a string, we must make */
     memcpy((char *)ptr, msg, len);    /* sure it is allocated on the heap. */
     ptr[len]=0;		       /* add null terminator. */
     struct string *retval = malloc(sizeof(struct string));
     retval->len = len;
     retval->ptr = ptr;
     /* printf("In new_string: len=%d, ptr=%s\n", (int) len, (char *)msg); */
     return retval;
}     

/* struct string *heap_allocate_string(char *msg) { */
/*      size_t len = (size_t) strlen(msg); */
/*      return new_string(msg, len); */
/* } */

/* struct stringArray testretarray(struct string foo) { */
/*      printf("testretarray argument received: len=%d, string=%s\n", foo.len, foo.ptr); */

/*      struct string *b = heap_allocate_string("This is a new struct string called b."); */
/*      struct string *c = heap_allocate_string("This is a new struct string called c."); */
/*      struct string *d = heap_allocate_string("This is a new struct string called d."); */
/*      struct string **ptr = malloc(sizeof(struct string *) * 3); */
/*      ptr[0] = b; ptr[1] = c; ptr[2] = d; */

/*      return (struct stringArray) {3, ptr}; */

/* } */

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
     LOGprintArray(retvals, "new_engine");
     return retvals;
}


struct stringArray delete_engine(struct string *eid_string) {
     struct string *ignore = &CONST_STRING("ignored12345");
     struct stringArray retvals = rosie_api("delete_engine", eid_string, ignore);
     LOGprintArray(retvals, "delete_engine");
     return retvals;
}

struct stringArray inspect_engine(struct string *eid_string) {
     struct string *ignore = &CONST_STRING("ignored678");
     struct stringArray retvals = rosie_api("inspect_engine", eid_string, ignore);
     LOGprintArray(retvals, "inspect_engine");
     return retvals;
}

struct stringArray match(struct string *eid_string, struct string *input) {
     struct stringArray retvals = rosie_api("match", eid_string, input);
     LOGprintArray(retvals, "match");
     return retvals;
}

void finalize() {
     lua_close(LL);
}
