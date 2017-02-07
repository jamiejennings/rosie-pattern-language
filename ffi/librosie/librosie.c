/*  -*- Mode: C; -*-                                                         */
/*                                                                           */
/* librosie.c    Expose the Rosie API                                        */
/*                                                                           */
/*  © Copyright IBM Corporation 2016.                                        */
/*  LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)  */
/*  AUTHOR: Jamie A. Jennings                                                */

/* To do:
   + One Lua state per engine
   + Have initialize create a table of Rosie api functions
   + Put debugging functions like stackDump inside #if DEBUG==1
   + Move json_decode and similar test functions to rtest
   - Check result of each malloc, and error out appropriately
*/

#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>

#include "lauxlib.h"
#include "lualib.h"

#include "librosie.h"

#define EXIT_OUT_OF_MEMORY -100

/* ----------------------------------------------------------------------------------------
 * DEBUG (LOGGING) 
 * ----------------------------------------------------------------------------------------
 */

#ifdef DEBUG
#define LOGGING 1
#else
#define LOGGING 0
#endif

#define LOG(msg) \
     do { if (LOGGING) fprintf(stderr, "%s:%d:%s(): %s", __FILE__, \
			       __LINE__, __func__, msg);	   \
	  fflush(NULL);						   \
     } while (0)

#define LOGf(fmt, ...) \
     do { if (LOGGING) fprintf(stderr, "%s:%d:%s(): " fmt, __FILE__, \
			       __LINE__, __func__, __VA_ARGS__);     \
	  fflush(NULL);						     \
     } while (0)

#define LOGstack(L)		      \
     do { if (LOGGING) stackDump(L);  \
	  fflush(NULL);		      \
     } while (0)

#define LOGprintArray(sa, caller_name) \
     do { if (LOGGING) print_stringArray(sa, caller_name);	\
	  fflush(NULL);						\
     } while (0)


#define new_TRUE_string() (rosieL_new_string((byte_ptr) "true", 4))
#define new_FALSE_string() (rosieL_new_string((byte_ptr) "false", 5))

#define prelude(L, name) \
     do { lua_getfield(L, -1, name); } while (0)

#define push(L, stringname) \
     do { if (stringname != NULL) lua_pushlstring(L, (char *) stringname->ptr, stringname->len); \
	  else lua_pushnil(L);						\
     } while (0)

/* ----------------------------------------------------------------------------------------
 * Utility functions
 * ----------------------------------------------------------------------------------------
 */

/* TODO: First try to load bin/bootstrap.luac and then fall back to src/core/bootstrap.lua */
static int bootstrap (lua_State *L, struct rosieL_string *rosie_home) {
     const char *bootscript = "/src/core/bootstrap.lua";
     LOG("About to bootstrap\n");
     char *name = malloc(rosie_home->len + strlen(bootscript) + 1);
     memcpy(name, rosie_home->ptr, rosie_home->len);
     memcpy(name+(rosie_home->len), bootscript, strlen(bootscript)+1); /* +1 copies the NULL terminator */
     int status = luaL_loadfile(L, name);
     if (status != LUA_OK) return status;
     status = lua_pcall(L, 0, LUA_MULTRET, 0);
     return status;
}

static int require_api (lua_State *L) {  
     int status;  
     lua_getglobal(L, "require");  
     lua_pushstring(L, "api");  
     status = lua_pcall(L, 1, 1, 0);                   /* call 'require(name)' */  
     if (status != LUA_OK) {
	  lua_pop(L, 1);	/* discard error because the details don't matter */
	  return FALSE;
     }
     /* IMPORTANT: leave the api table on the stack!
      * For each call to the API, we will index into this table to
      * find the Lua function that implements the API.  An
      * alternative, which may be slightly faster, is to store each
      * API function in LUA_REGISTRY, each with its own unique
      * integer key (see luaL_ref).
      */
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
        printf("  ");
      }
      printf("\n");
      fflush(NULL);
    }

static void print_stringArray(struct rosieL_stringArray sa, char *caller_name) {
     printf("Values returned in stringArray from: %s\n", caller_name);
     printf("  Number of strings: %d\n", sa.n);
     for (uint32_t i=0; i<sa.n; i++) {
	  struct rosieL_string *cstrptr = sa.ptr[i];
	  printf("  [%d] len = %d, ptr = %s\n", i, cstrptr->len, cstrptr->ptr);
     }
     fflush(NULL);
}

/* ----------------------------------------------------------------------------------------
 * Exported functions
 * ----------------------------------------------------------------------------------------
 */

/* forward ref */
static struct rosieL_stringArray call_api(lua_State *L, char *api_name, int nargs);
     
void *rosieL_initialize(struct rosieL_string *rosie_home, struct rosieL_stringArray *msgs) {
     lua_State *L = luaL_newstate();
     if (L == NULL) {
	  print_error_message("error during initialization: not enough memory");
	  exit(EXIT_OUT_OF_MEMORY);
     }
/* 
   luaL_checkversion checks whether the core running the call, the core that created the Lua state,
   and the code making the call are all using the same version of Lua. Also checks whether the core
   running the call and the core that created the Lua state are using the same address space.
*/   
  luaL_checkversion(L);
  luaL_openlibs(L);
  lua_pushlstring(L, (char *) rosie_home->ptr, rosie_home->len);
  lua_setglobal(L, "ROSIE_HOME");
  LOGf("Initializing Rosie, where ROSIE_HOME = %s\n", rosie_home->ptr);
  int status = bootstrap(L, rosie_home);
  LOGf("Call to bootstrap() completed: status=%d\n", status); fflush(NULL);
  if (status==LUA_OK) {
       LOG("Bootstrap succeeded\n"); fflush(NULL);
       fflush(stderr);
       if (require_api(L)) { 
	    lua_getfield(L, -1, "initialize");
	    struct rosieL_stringArray retvals = call_api(L, "initialize", 0);
	    msgs->n = retvals.n;
	    msgs->ptr = retvals.ptr;
	    return L;
       }
       else {
	    struct rosieL_string **list = malloc(sizeof(struct rosieL_string *) * 2);
	    list[0] = new_FALSE_string();
	    char *str_ptr;
	    int n = asprintf(&str_ptr, "Internal error: cannot load api (%s)", lua_tostring(L, -1));
	    if (n < 0) exit(EXIT_OUT_OF_MEMORY);  
	    list[1] = malloc(sizeof(struct rosieL_string));
	    list[1]->ptr = (byte_ptr) str_ptr;
	    list[1]->len = n;
	    lua_close(L);
	    msgs->n = 2;
	    msgs->ptr = list;
	    return NULL;
       }
  }
  LOG("Bootstrap failed... building return value array\n");
  struct rosieL_string **list = malloc(sizeof(struct rosieL_string *) * 2);
  list[0] = new_FALSE_string();
  list[1] = malloc(sizeof(struct rosieL_string));
  if (luaL_checkstring(L, -1)) {
       LOG("There is an error message on the Lua stack\n");
       byte_ptr str = (byte_ptr) lua_tolstring(L, -1, (size_t *) &(list[1]->len));
       LOGf("The message has length %d and reads: %s\n", list[1]->len, str);
       list[1] = rosieL_new_string(str, list[1]->len);
  }
  else {
       const char *msg =  "Unknown error encountered while trying to bootstrap";
       LOGf("%s\n", msg);
       list[1] = rosieL_new_string((byte_ptr) msg, strlen(msg));
  }       
  LOG("About to close the Lua state... ");
  lua_close(L);
  LOG("Done closing the Lua state.");
  msgs->n = 2;
  msgs->ptr = list;
  return NULL;
}

struct rosieL_stringArray construct_retvals(lua_State *L) {
     struct rosieL_stringArray retvals;
     size_t nretvals = lua_rawlen(L, -1);
     struct rosieL_string **list = malloc(sizeof(struct rosieL_string *) * nretvals);
     size_t len;
     for (size_t i=0; i<nretvals; i++) {
	  int t = lua_rawgeti(L, -1, (lua_Integer) i+1);    /* lua has 1-based indexing */
	  list[i] = malloc(sizeof(struct rosieL_string));
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
	  LOGf("  Encoded as struct rosieL_string: len=%d ptr=%s\n", (int) list[i]->len, list[i]->ptr);
	  lua_pop(L, 1);
     }
     retvals.n = nretvals;
     retvals.ptr = list;
     lua_pop(L, 1);		/* pop the api call's results table */
     return retvals;
}

struct rosieL_string *rosieL_new_string(byte_ptr msg, size_t len) {
     byte_ptr ptr = malloc(len+1);     /* to return a string, we must make */
     memcpy((char *)ptr, msg, len);    /* sure it is allocated on the heap. */
     ptr[len]=0;		       /* add null terminator. */
     struct rosieL_string *retval = malloc(sizeof(struct rosieL_string));
     retval->len = len;
     retval->ptr = ptr;
     /* printf("In new_string: len=%d, ptr=%s\n", (int) len, (char *)msg); */
     return retval;
}     

struct rosieL_stringArray *rosieL_new_stringArray() {
     return malloc(sizeof(struct rosieL_stringArray));
}

void rosieL_free_string_ptr(struct rosieL_string *ref) {
     free(ref->ptr);
     free(ref);
}

void rosieL_free_string(struct rosieL_string s) {
     free(s.ptr);
}

void rosieL_free_stringArray(struct rosieL_stringArray r) {
     struct rosieL_string **s = r.ptr;
     for (uint32_t i=0; i<r.n; i++) {
	  free(s[i]->ptr);
	  free(s[i]);
     }
     free(r.ptr);
}

void rosieL_free_stringArray_ptr(struct rosieL_stringArray *ref) {
     rosieL_free_stringArray(*ref);
     free(ref);
}

static struct rosieL_stringArray call_api(lua_State *L, char *api_name, int nargs) {
     LOGf("About to call %s and nargs=%d\n", api_name, nargs);  
     LOGstack(L);  
     /* API CALL */
     lua_call(L, nargs, 1); 
     LOG("Stack immediately after lua_call:\n");
     LOGstack(L);
     
     if (lua_istable(L, -1) != TRUE) {
	  print_error_message(
	       lua_pushfstring(L,
			       "librosie internal error: return value of %s not a table",
			       api_name));
	  exit(-1);
     }

     struct rosieL_stringArray retvals = construct_retvals(L);

     LOGf("Stack at end of call to Rosie api: %s\n", api_name); 
     LOGstack(L); 

     LOGprintArray(retvals, api_name);
     return retvals;
}
     
void rosieL_finalize(void *L) {
     lua_close(L);
}

#include "librosie_gen.c"
