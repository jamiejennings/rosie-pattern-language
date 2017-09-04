/*  -*- Mode: C; -*-                                                         */
/*                                                                           */
/* librosie.c    Expose the Rosie API                                        */
/*                                                                           */
/*  © Copyright IBM Corporation 2016, 2017                                   */
/*  LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)  */
/*  AUTHOR: Jamie A. Jennings                                                */

/* To do:
   + One Lua state per engine
   + Have initialize create a table of Rosie api functions
   + Put debugging functions like stackDump inside #if DEBUG==1
   + Move json_decode and similar test functions to rtest
   - Check result of each malloc, and error out appropriately
*/


#include <assert.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>

#include "lauxlib.h"
#include "lualib.h"

#include "librosie.h"

#include <dlfcn.h>
#include <libgen.h>

int luaopen_lpeg (lua_State *L);
int luaopen_cjson (lua_State *L);

#define BOOTSCRIPT "/lib/boot.luac"

#define ERR_OUT_OF_MEMORY -2
#define ERR_SYSCALL_FAILED -3
#define ERR_ENGINE_CALL_FAILED -4

/* ----------------------------------------------------------------------------------------
 * DEBUG (LOGGING) 
 * ----------------------------------------------------------------------------------------
 */

#define DEBUG 1

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

static char libname[MAXPATHLEN];
static char libdir[MAXPATHLEN];
static char bootscript[MAXPATHLEN];

static void display (const char *msg) {
  fprintf(stderr, "%s: ", libname);
  fprintf(stderr, "%s\n", msg);
  fflush(NULL);
}

static void set_libinfo() {
  Dl_info dl;
  int ok = dladdr((void *)set_libinfo, &dl);
  if (!ok) {
    display("librosie: call to dladdr failed");
    exit(ERR_SYSCALL_FAILED);
  }
  LOGf("dli_fname is %s\n", dl.dli_fname);
  if (!basename_r((char *)dl.dli_fname, libname) ||
      !dirname_r((char *)dl.dli_fname, libdir)) {
    display("librosie: call to basename/dirname failed");
    exit(ERR_SYSCALL_FAILED);
  }
  LOGf("libdir is %s, and libname is %s\n", libdir, libname);
}

static void set_bootscript() {
  size_t bootscript_len;
  static char *last;
  if (!*libdir) set_libinfo();
  bootscript_len = strnlen(BOOTSCRIPT, MAXPATHLEN);
  last = stpncpy(bootscript, libdir, (MAXPATHLEN - bootscript_len - 1));
  last = stpncpy(last, BOOTSCRIPT, bootscript_len);
  *last = '\0';
  assert(((unsigned long)(last-bootscript))==(strnlen(libdir, MAXPATHLEN)+bootscript_len));
  assert((last-bootscript) < MAXPATHLEN);
  LOGf("Bootscript filename set to %s\n", bootscript);
}

static int boot (lua_State *L, struct rosieL_string *rosie_home) {
  if (!*bootscript) set_bootscript();
  assert(bootscript);
  LOGf("Booting rosie from %s\n", bootscript);
  int status = luaL_loadfile(L, bootscript);
  if (status != LUA_OK) return status;
  LOG("Loadfile succeeded\n");
  status = lua_pcall(L, 0, LUA_MULTRET, 0);
  if (status != LUA_OK) return status;
  LOG("Call to loaded thunk succeeded\n");
  lua_pushlstring(L, rosie_home->ptr, rosie_home->len);
  status = lua_pcall(L, 1, LUA_MULTRET, 0);
  LOG("Call to boot function succeeded\n");
  return (status==LUA_OK);
}

/* ----------------------------------------------------------------------------------------
 * Debug functions
 * ----------------------------------------------------------------------------------------
 */

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
     
void *rosieL_initialize(struct rosieL_string *rosie_home) {
  lua_State *L = luaL_newstate();
  if (L == NULL) {
    display("Cannot initialize: not enough memory");
    exit(ERR_OUT_OF_MEMORY);
  }
  /* 
     luaL_checkversion checks whether the core running the call, the core that created the Lua state,
     and the code making the call are all using the same version of Lua. Also checks whether the core
     running the call and the core that created the Lua state are using the same address space.
  */   
  luaL_checkversion(L);
  luaL_openlibs(L);

  if (!boot(L, rosie_home)) {
    LOG("Bootstrap failed\n");
    return NULL;
  }
  LOG("Bootstrap succeeded\n");
  if (!lua_checkstack(L, 6)) {
    display("Cannot initialize: not enough memory for stack expansion");
    exit(ERR_OUT_OF_MEMORY);
  }
  lua_getglobal(L, "rosie");
  lua_getfield(L, -1, "engine");
  lua_getfield(L, -1, "new");
  lua_call(L, 0, 1);
  lua_copy(L, -1, 1);
  lua_pop(L, 3);

#if (LOGGING)
  display(luaL_tolstring(L, -1, NULL)); /* convert copy of engine to a string */
  lua_pop(L, 1);		/* remove string */
#endif

  LOG("Engine created\n");
  return L;
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
	  display(
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

/* #include "librosie_gen.c" */
