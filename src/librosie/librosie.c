/*  -*- Mode: C; -*-                                                         */
/*                                                                           */
/* librosie.c    Expose the Rosie API                                        */
/*                                                                           */
/*  © Copyright IBM Corporation 2016, 2017                                   */
/*  LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)  */
/*  AUTHOR: Jamie A. Jennings                                                */

/* Protocol:
 * 
 * Call new() to get an engine.  Every thread must have its own engine.
 *
 * Call free() to destroy an engine and free its memory.
 *
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

/* int (*r_match_C)(lua_State *L);	/\* defined in lptree.c *\/ */
/* rBuffer *(*r_newbuffer_wrap)(lua_State *L, char *data, size_t len); /\* defined in rbuf.c *\/ */
typedef void *(*func_ptr_t)();
int (*fp_r_match_C)();	/* defined in lptree.c */ 
typedef rBuffer* (*foo_t)(lua_State *L, char *data, size_t len);
foo_t fp_r_newbuffer_wrap;		/* defined in rbuf.c */ 

/* ----------------------------------------------------------------------------------------
 * Paths relative to where librosie.so is found (for example):
 *  /usr/local/lib/librosie.so => 
 *    libname = librosie.so
 *    dirname = /usr/local/lib
 *    rosiehomedir = /usr/local/lib/rosie
 *    bootscript = /usr/local/lib/rosie/lib/boot.luac
 * ----------------------------------------------------------------------------------------
 */
#define ROSIEHOME "/rosie"
#define BOOTSCRIPT "/lib/boot.luac"

static char libname[MAXPATHLEN];
static char libdir[MAXPATHLEN];
static char rosiehomedir[MAXPATHLEN];
static char bootscript[MAXPATHLEN];

/* ---------------------------------------------------------------------------------------- 
 * The following keys are used to store values in the lua registry 
 * ----------------------------------------------------------------------------------------
 */
enum KEYS {
  engine_key = 0,
  engine_match_key,
  rosie_key,
  rplx_table_key,
  json_encoder_key,
  alloc_limit_key,
  prev_string_result_key,
  KEY_ARRAY_SIZE
};

static int key_array[KEY_ARRAY_SIZE];

#define keyval(key) ((void *)&key_array[(key)])

#define get_registry(key) \
  do { lua_pushlightuserdata(L, keyval(key));  \
       lua_gettable(L, LUA_REGISTRYINDEX);     \
  } while (0)

/* Call set_registry with val on top of stack.  Stack will be unchanged after call. */
#define set_registry(key) \
  do { lua_pushlightuserdata(L, keyval(key)); \
       lua_pushvalue(L, -2);	              \
       lua_settable(L, LUA_REGISTRYINDEX);    \
  } while (0)


/* ----------------------------------------------------------------------------------------
 * Logging and debugging
 * ----------------------------------------------------------------------------------------
 */

/* Compile with DEBUG=1 to enable logging */
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
  do { if (LOGGING) {		      \
    fprintf(stderr, "%s:%d:%s(): lua stack dump: ", __FILE__,	     \
	    __LINE__, __func__);			     \
    stackDump(L);						     \
    fflush(NULL);						     \
  } \
} while (0)

static void stackDump (lua_State *L) {
      int i;
      int top = lua_gettop(L);
      if (top==0) { fprintf(stderr, "EMPTY STACK\n"); return;}
      for (i = top; i >= 1; i--) {
        int t = lua_type(L, i);
        switch (t) {
          case LUA_TSTRING:  /* strings */
	    fprintf(stderr, "%d: '%s'", i, lua_tostring(L, i));
            break;
          case LUA_TBOOLEAN:  /* booleans */
	    fprintf(stderr, "%d: %s", i, (lua_toboolean(L, i) ? "true" : "false"));
            break;
          case LUA_TNUMBER:  /* numbers */
	    fprintf(stderr, "%d: %g", i, lua_tonumber(L, i));
            break;
          default:  /* other values */
	    fprintf(stderr, "%d: %s", i, lua_typename(L, t));
            break;
        }
        fprintf(stderr, "  ");
      }
      fprintf(stderr, "\n");
    }


#ifdef DEBUG
#define CHECK_TYPE(label, typ, expected_typ) \
  do { if (DEBUG) check_type((label), (typ), (expected_typ)); } while (0)
#else
#define CHECK_TYPE(label, typ, expected_typ)
#endif

void check_type(const char *thing, int t, int expected) {
  if (t != expected)
    LOGf("type mismatch for %s.  received %d, expected %d.\n", thing, t, expected);
}

/* ----------------------------------------------------------------------------------------
 * Utility functions
 * ----------------------------------------------------------------------------------------
 */

static void display (const char *msg) {
  fprintf(stderr, "%s: ", libname);
  fprintf(stderr, "%s\n", msg);
  fflush(NULL);
}

static int encoder_name_to_code(const char *name) {
  r_encoder_t *entry = r_encoders;
  while (entry->name) {
    if (!strncmp(name, entry->name, MAX_ENCODER_NAME_LENGTH)) return entry->code;
    entry++;
  }
  return 0;
}

static str string_from_const(const char *msg) {
  size_t len = strnlen(msg, MAXPATHLEN); /* arbitrary but small-ish limit */
  return rosie_new_string((byte_ptr) msg, len);
}

str rosie_new_string(byte_ptr msg, size_t len) {
  str retval;
  retval.len = len;
  retval.ptr = malloc(len+1);
  if (!retval.ptr) {
    display("Out of memory (new1)");
    return retval;
  }
  memcpy((char *)retval.ptr, msg, retval.len);    /* sure it is allocated on the heap. */
  retval.ptr[len]=0;		/* add null terminator. */
  return retval;
}

str *rosie_new_string_ptr(byte_ptr msg, size_t len) {
  str temp = rosie_new_string(msg, len);
  str *retval = malloc(sizeof(str));
  if (!retval) {
    display("Out of memory (new2)");
    return NULL;
  }
  retval->len = temp.len;
  retval->ptr = temp.ptr;
  return retval;
}     

void rosie_free_string_ptr(str *ref) {
     free(ref->ptr);
     free(ref);
}

void rosie_free_string(str s) {
     free(s.ptr);
}

static void set_libinfo() {
  Dl_info dl;
  char *base, *dir;
  int ok = dladdr((void *)set_libinfo, &dl);
  if (!ok) {
    display("librosie: call to dladdr failed");
    exit(ERR_SYSCALL_FAILED);
  }
  LOGf("dli_fname is %s\n", dl.dli_fname);
  base = basename((char *)dl.dli_fname);
  dir = dirname((char *)dl.dli_fname);
  if (!base || !dir) {
    display("librosie: call to basename/dirname failed");
    exit(ERR_SYSCALL_FAILED);
  }
  strncpy(libname, base, MAXPATHLEN);
  strncpy(libdir, dir, MAXPATHLEN);
  LOGf("libdir is %s, and libname is %s\n", libdir, libname);
}

static void set_bootscript() {
  size_t len;
  static char *last;
  if (!*libdir) set_libinfo();
  /* set rosiehomedir */
  len = strnlen(ROSIEHOME, MAXPATHLEN);
  last = stpncpy(rosiehomedir, libdir, (MAXPATHLEN - len - 1));
  last = stpncpy(last, ROSIEHOME, len);
  *last = '\0';
  /* set bootscript (absolute path to boot script) */
  len = strnlen(BOOTSCRIPT, MAXPATHLEN);
  last = stpncpy(bootscript, rosiehomedir, (MAXPATHLEN - len - 1));
  last = stpncpy(last, BOOTSCRIPT, len);
  *last = '\0';
  assert((last-bootscript) < MAXPATHLEN);
  LOGf("Bootscript filename set to %s\n", bootscript);
}

static int boot (lua_State *L, str *errors) {
  char rpeg_path[MAXPATHLEN];
  char *msg = NULL;
  void *lib;
  if (!*bootscript) set_bootscript();
  assert(bootscript);
  LOGf("Booting rosie from %s\n", bootscript);

/* TODO: find a better way to obtain the handle to rpeg.so */
#define RPEG_LOCATION "/lib/lpeg.so"
  char *next = stpncpy(rpeg_path, rosiehomedir, MAXPATHLEN); 
  if ((MAXPATHLEN - (unsigned int)(next - rpeg_path + 1)) < strlen(RPEG_LOCATION)) {
    *errors = string_from_const("rpeg_path exceeds MAXPATHLEN");
    return FALSE;
  }
  strncpy(next, RPEG_LOCATION, (MAXPATHLEN - (next - rpeg_path + 1)));
  LOGf("rpeg path (calculated) is %s\n", rpeg_path);
  
  lib = dlopen(rpeg_path, RTLD_NOW); /* reopen to get handle */
  if (lib == NULL) LOG("*** dlopen returned NULL\n");
  
  int status = luaL_loadfile(L, bootscript);
  if (status != LUA_OK) {
    LOG("Failed to read boot code (using loadfile)\n");
    if (asprintf(&msg, "missing or corrupt rosie boot loader %s", bootscript)) {
      *errors = string_from_const(msg);
    }
    else {
      *errors = string_from_const("cannot find rosie boot code");
    }
    return FALSE;
  }
  LOG("Reading of boot code succeeded (using loadfile)\n");
  status = lua_pcall(L, 0, LUA_MULTRET, 0);
  if (status != LUA_OK) {
    LOG("Loading of boot code failed\n");
    if (asprintf(&msg, "loading failed for %s", bootscript)) {
      *errors = string_from_const(msg);
    }
    else {
      *errors = string_from_const("loading of boot code failed");
    }
    return FALSE;
  }
  LOG("Loading of boot code succeeded\n");
  lua_pushlstring(L, (const char *)rosiehomedir, strnlen(rosiehomedir, MAXPATHLEN));
  status = lua_pcall(L, 1, LUA_MULTRET, 0);
  if (status!=LUA_OK) {
    LOG("Boot function failed.  Lua stack is: \n");
    LOGstack(L);
    *errors = string_from_const("execution of boot loader failed");
    return FALSE;
  }
  LOG("Boot function succeeded\n");

  fp_r_match_C = dlsym(lib, "r_match_C");

  if ((msg = dlerror()) != NULL) LOGf("*** err = %s]\n", msg);

  fp_r_newbuffer_wrap = (foo_t) dlsym(lib, "r_newbuffer_wrap");

  if ((msg = dlerror()) != NULL) LOGf("*** err = %s]\n", msg);

  if ((fp_r_match_C == NULL) || (fp_r_newbuffer_wrap == NULL)) {
    LOG("Failed to find rpeg functions\n");
    LOGstack(L);
    *errors = string_from_const("binding of rpeg functions failed");
    return FALSE;
  }

  return TRUE;
}

str *to_json_string(lua_State *L, int pos) {
     size_t len;
     byte_ptr str;
     int t;
     int top = lua_gettop(L);
     get_registry(json_encoder_key);
     lua_pushvalue(L, pos-1);                /* offset because we pushed json_encoder */
     t = lua_pcall(L, 1, LUA_MULTRET, 0);
     if (t != LUA_OK) {
       LOG("call to json encoder failed\n"); /* more detail may not be useful to the user */
       LOGstack(L);
       return NULL;
     }
     if ((lua_gettop(L) - top) > 1) {
       /* Top of stack is error msg */
       LOG("call to json encoder returned more than one value\n");
       if (lua_isstring(L, -1) && lua_isnil(L, -2)) {
	 /* FUTURE: return the error from the json encoder to the client */
	 LOGf("error message from json encoder: %s\n", lua_tolstring(L, -1, NULL));
	 LOGstack(L);
	 return NULL;
       }
       else {
	 /* Something really strange happened!  Is there any useful info to return? */
	 LOG("call to json encoder returned unexpected values\n");
	 LOGstack(L);
	 return NULL;
       }
     }
     str = (byte_ptr) lua_tolstring(L, -1, &len);
     return rosie_new_string_ptr(str, len);
}

/* ----------------------------------------------------------------------------------------
 * Exported functions
 * ----------------------------------------------------------------------------------------
 */

int rosie_set_alloc_limit(lua_State *L, int newlimit) {
  int memusg, actual_limit;
  if ((newlimit != 0) && (newlimit < MIN_ALLOC_LIMIT_MB)) return ERR_ENGINE_CALL_FAILED;
  else {
    lua_gc(L, LUA_GCCOLLECT, 0);
    lua_gc(L, LUA_GCCOLLECT, 0);	/* second time to free resources marked for finalization */
    memusg = lua_gc(L, LUA_GCCOUNT, 0); /* KB */
    actual_limit = memusg + (newlimit * 1024);
    lua_pushinteger(L, (newlimit == 0) ? 0 : actual_limit);
    set_registry(alloc_limit_key);
    lua_pop(L, 1);
    if (newlimit == 0) LOGf("set alloc limit to UNLIMITED above current usage level of %0.1f MB\n", memusg/1024.0);
    else LOGf("set alloc limit to %d MB above current usage level of %0.1f MB\n", newlimit, memusg/1024.0);
  }
  return SUCCESS;
}

void *rosie_new(str *errors) {
  int t;
  lua_State *L = luaL_newstate();
  if (L == NULL) {
    *errors = string_from_const("not enough memory to initialize");
    return NULL;
  }
  luaL_checkversion(L);		/* Ensures several critical things needed to use Lua */
  luaL_openlibs(L);

  if (!boot(L, errors)) {
    return NULL;		/* errors already set by boot */
  }
  if (!lua_checkstack(L, 6)) {
    display("Cannot initialize: not enough memory for stack");
    *errors = string_from_const("not enough memory for stack");
    return NULL;
  }
  t = lua_getglobal(L, "rosie");
  CHECK_TYPE("rosie", t, LUA_TTABLE);
  set_registry(rosie_key);
  
  t = lua_getfield(L, -1, "engine");
  CHECK_TYPE("engine", t, LUA_TTABLE);
  t = lua_getfield(L, -1, "new");
  CHECK_TYPE("engine.new", t, LUA_TFUNCTION);
  t = lua_pcall(L, 0, 1, 0);
  if (t != LUA_OK) {
    display("rosie.engine.new() failed");
    *errors = string_from_const("rosie.engine.new() failed");
    return NULL;
  }

  /* engine instance is at top of stack */
  set_registry(engine_key);
  t = lua_getfield(L, -1, "match");
  CHECK_TYPE("engine.match", t, LUA_TFUNCTION);
  set_registry(engine_match_key);

#if (LOGGING)
  display(luaL_tolstring(L, -1, NULL));
  lua_pop(L, 1); 
#endif

  lua_createtable(L, INITIAL_RPLX_SLOTS, 0);
  set_registry(rplx_table_key);

  lua_getglobal(L, "rosie");
  t = lua_getfield(L, -1, "env");
  CHECK_TYPE("rosie.env", t, LUA_TTABLE);
  t = lua_getfield(L, -1, "cjson");
  CHECK_TYPE("rosie.env.cjson", t, LUA_TTABLE);
  t = lua_getfield(L, -1, "encode");
  CHECK_TYPE("rosie.env.cjson.encode", t, LUA_TFUNCTION);
  set_registry(json_encoder_key);

  rosie_set_alloc_limit(L, INITIAL_ALLOC_LIMIT_MB);

  lua_settop(L, 0);
  LOG("Engine created\n");
  return L;
}

/* N.B. Client must free retval */
int rosie_config(lua_State *L, str *retval) {
  int t;
  str *r;
  get_registry(rosie_key);
  t = lua_getfield(L, -1, "config");
  CHECK_TYPE("config", t, LUA_TFUNCTION);
  t = lua_pcall(L, 0, 1, 0);
  if (t != LUA_OK) {
    LOG("rosie.config() failed");
    lua_settop(L, 0);
    return ERR_ENGINE_CALL_FAILED;
  }
  r = to_json_string(L, -1);
  if (r == NULL) {
    LOG("in config(), could not convert config information to json\n");
    lua_settop(L, 0);
    return ERR_ENGINE_CALL_FAILED;
  }
  retval->len = r->len;
  retval->ptr = r->ptr;
  lua_settop(L, 0);
  return SUCCESS;
}

int rosie_setlibpath_engine(lua_State *L, char *newpath) {
  int t;
  get_registry(engine_key);
  t = lua_getfield(L, -1, "set_libpath");
  CHECK_TYPE("engine.set_libpath()", t, LUA_TFUNCTION);
  lua_pushvalue(L, -2);
  lua_pushstring(L, (const char *)newpath);
  t = lua_pcall(L, 2, 0, 0);
  if (t != LUA_OK) {
    LOG("engine.set_libpath() failed\n");
    lua_settop(L, 0);
    return ERR_ENGINE_CALL_FAILED;
  }
#if LOGGING
  do {
    get_registry(engine_key);
    t = lua_getfield(L, -1, "searchpath");
    LOGf("searchpath is now: %s\n", lua_tostring(L, -1));
  } while (0);
#endif
  lua_settop(L, 0);
  return SUCCESS;
}

int rosie_free_rplx(lua_State *L, int pat) {
  LOGf("freeing rplx object with index %d\n", pat);
  get_registry(rplx_table_key);
  luaL_unref(L, -1, pat);
  lua_settop(L, 0);
  return SUCCESS;
}

/* N.B. Client must free errors */
int rosie_compile(lua_State *L, str *expression, int *pat, str *errors) {
  int t;
  str *temp_rs;

  if (!pat) {
    LOG("null pointer passed to compile for pattern argument");
    lua_settop(L, 0);
    return ERR_ENGINE_CALL_FAILED;
  }
  if (!expression) {
    LOG("null pointer passed to compile for expression argument");
    lua_settop(L, 0);
    return ERR_ENGINE_CALL_FAILED;
  }  

#if LOGGING
  if (lua_gettop(L)) LOG("Entering compile(), stack is NOT EMPTY!\n");
#endif  

  get_registry(rplx_table_key);

  get_registry(engine_key);
  t = lua_getfield(L, -1, "compile");
  CHECK_TYPE("compile", t, LUA_TFUNCTION);

  lua_replace(L, -2); /* overwrite engine table with compile function */
  get_registry(engine_key);

  lua_pushlstring(L, (const char *)expression->ptr, expression->len);
  t = lua_pcall(L, 2, 2, 0);
  if (t != LUA_OK) {
    LOG("compile() failed");
    LOGstack(L);
    lua_settop(L, 0);
    return ERR_ENGINE_CALL_FAILED;
  }

  if ( lua_isboolean(L, -2) ) {
    *pat = 0;
    CHECK_TYPE("compile errors", lua_type(L, -1), LUA_TTABLE);
    temp_rs = to_json_string(L, -1);
    if (temp_rs == NULL) {
      LOG("in compile() could not convert compile errors to json\n");
      lua_settop(L, 0);
      return ERR_ENGINE_CALL_FAILED;
    }
    errors->len = temp_rs->len;
    errors->ptr = temp_rs->ptr;
    lua_settop(L, 0);
    return SUCCESS;
  }
  
  lua_pushvalue(L, -2);
  CHECK_TYPE("new rplx object", lua_type(L, -1), LUA_TTABLE);
  *pat = luaL_ref(L, 1);
#if LOGGING
  if (*pat == LUA_REFNIL) LOG("error storing rplx object\n");
#endif
  LOGf("storing rplx object at index %d\n", *pat);

  temp_rs = to_json_string(L, -1);
    if (temp_rs == NULL) {
      LOG("in compile(), could not convert warning information to json\n");
      lua_settop(L, 0);
      return ERR_ENGINE_CALL_FAILED;
    }
  errors->len = temp_rs->len;
  errors->ptr = temp_rs->ptr;

  lua_settop(L, 0);
  return SUCCESS;
}

static inline void collect_if_needed(lua_State *L) {
  int limit, memusg;
  get_registry(alloc_limit_key);
  limit = lua_tointeger(L, -1);	/* nil will convert to zero */
  lua_pop(L, 1);
  if (limit) {
    memusg = lua_gc(L, LUA_GCCOUNT, 0);
    if (memusg > limit) {
      LOGf("invoking collection of %0.1f MB heap\n", memusg/1024.0);
      lua_gc(L, LUA_GCCOLLECT, 0);
#if (LOGGING)
      memusg = lua_gc(L, LUA_GCCOUNT, 0);
      LOGf("post-collection heap has %0.1f MB\n", memusg/1024.0);
#endif
    }
  }
}

#define set_match_error(match, errno) \
  do { (*(match)).data.ptr = NULL;    \
    (*(match)).data.len = (errno);    \
  } while (0);


int rosie_match(lua_State *L, int pat, int start, char *encoder_name, str *input, match *match) {
  int t, encoder;
  size_t temp_len;
  unsigned char *temp_str;
  rBuffer *buf;

  collect_if_needed(L);
  if (!pat)
    LOGf("rosie_match() called with invalid compiled pattern reference: %d\n", pat);
  else {
    get_registry(rplx_table_key);
    t = lua_rawgeti(L, -1, pat);
    if (t == LUA_TTABLE) goto have_pattern;
  }
  set_match_error(match, ERR_NO_PATTERN);
  lua_settop(L, 0);
  return SUCCESS;

have_pattern:

  /* The encoder values that do not require Lua processing
   * take a different code path from the ones that do.  When no
   * Lua processing is needed, we can (1) use a lightuserdata to hold
   * a ptr to the rosie_string holding the input, and (2) call into a
   * refactored rmatch such that it allows this. 
   *
   * Otherwise, we call the lua function rplx.match().
   */

  encoder = encoder_name_to_code(encoder_name);
  if (!encoder) {
    /* Path through Lua */
    t = lua_getfield(L, -1, "match");
    CHECK_TYPE("rplx.match()", t, LUA_TFUNCTION);
    lua_replace(L, 1);
    lua_settop(L, 2);
    /* Don't make a copy of the input.  Wrap it in an rbuf, which will
       be gc'd later (but will not free the original source data. */
    (*fp_r_newbuffer_wrap)(L, (char *)input->ptr, input->len); 
    lua_pushinteger(L, start);
    lua_pushstring(L, encoder_name);
    assert(lua_gettop(L) == 5);
  }
  else {
    /* Path through C */
    t = lua_getfield(L, -1, "pattern");
    CHECK_TYPE("rplx pattern slot", t, LUA_TTABLE);
    t = lua_getfield(L, -1, "peg");
    CHECK_TYPE("rplx pattern peg slot", t, LUA_TUSERDATA);
    lua_pushcfunction(L, *fp_r_match_C);
    lua_copy(L, -1, 1);
    lua_copy(L, -2, 2);
    lua_settop(L, 2);
    lua_pushlightuserdata(L, input); 
    lua_pushinteger(L, start);
    lua_pushinteger(L, encoder);
  }
  
  t = lua_pcall(L, 4, 5, 0); 
  if (t != LUA_OK) {  
    LOG("match() failed\n");  
    LOGstack(L); 
    lua_settop(L, 0); 
    return ERR_ENGINE_CALL_FAILED;  
  }  

  (*match).tmatch = lua_tointeger(L, -1);
  (*match).ttotal = lua_tointeger(L, -2);
  (*match).abend = lua_toboolean(L, -3);
  (*match).leftover = lua_tointeger(L, -4);
  lua_pop(L, 4);

  buf = lua_touserdata(L, -1);
  if (buf) {
    (*match).data.ptr = (unsigned char *)buf->data;
    (*match).data.len = buf->n;
  }
  else if (lua_isboolean(L, -1)) {
    set_match_error(match, ERR_NO_MATCH);
  }
  else if (lua_isstring(L, -1)) {
    if (encoder) {
      LOG("Invalid return type from rmatch (string)\n");
      match = NULL;
      lua_settop(L, 0);
      return ERR_ENGINE_CALL_FAILED;
    }
    /* The client does not need to manage the storage for match
     * results when they are in an rBuffer (userdata), so we do not
     * want the client to manage the storage when it has the form of a
     * Lua string (returned by common.rmatch).  So we alloc the
     * string, and stash a pointer to it in the registry, to be freed
     * the next time around.
    */
    get_registry(prev_string_result_key);
    if (lua_isuserdata(L, -1)) {
      str *rs = lua_touserdata(L, -1);
      rosie_free_string_ptr(rs);
    }
    lua_pop(L, 1);
    temp_str = (unsigned char *)lua_tolstring(L, -1, &temp_len);
    str *rs = rosie_new_string_ptr(temp_str, temp_len);
    lua_pushlightuserdata(L, (void *) rs);
    set_registry(prev_string_result_key);
    (*match).data.ptr = rs->ptr;
    (*match).data.len = rs->len;
  }
  else {
    t = lua_type(L, -1);
    LOGf("Invalid return type from rmatch (%d)\n", t);
    match = NULL;
    lua_settop(L, 0);
    return ERR_ENGINE_CALL_FAILED;
  }

  lua_settop(L, 0);
  return SUCCESS;
}

/* N.B. Client must free trace */
int rosie_trace(lua_State *L, int pat, int start, char *trace_style, str *input, int *matched, str *trace) {
  int t;
  str *rs;
  
  collect_if_needed(L);

  get_registry(engine_key);
  t = lua_getfield(L, -1, "trace");
  CHECK_TYPE("engine.trace()", t, LUA_TFUNCTION);
  get_registry(engine_key);	/* first arg to trace */

  if (!pat)
    LOGf("rosie_trace() called with invalid compiled pattern reference: %d\n", pat);
  else {
    get_registry(rplx_table_key);
    t = lua_rawgeti(L, -1, pat); /* arg 2 to trace*/
    if (t == LUA_TTABLE) goto have_pattern;
  }
  (*trace).ptr = NULL;
  (*trace).len = ERR_NO_PATTERN;
  lua_settop(L, 0);
  return SUCCESS;

have_pattern:

  lua_replace(L, -2); 		/* overwrite rplx table with rplx object */
  if (!trace_style) {
    LOG("rosie_trace() called with null trace_style arg\n");
    (*trace).ptr = NULL;
    (*trace).len = ERR_NO_TRACESTYLE;
    lua_settop(L, 0);
    return SUCCESS;
  }

  lua_pushlstring(L, (const char *)input->ptr, input->len); /* arg 3 */
  lua_pushinteger(L, start);	                            /* arg 4 */
  lua_pushstring(L, trace_style);                           /* arg 5 */

  t = lua_pcall(L, 5, 3, 0); 
  if (t != LUA_OK) {  
    LOG("trace() failed\n");  
    LOGstack(L); 
    lua_settop(L, 0); 
    return ERR_ENGINE_CALL_FAILED;  
  }  

  /* The first return value from trace indicates whether the pattern
     compiled, and we are always sending in a compiled pattern, so the
     first return value is always true. 
  */
  assert( lua_isboolean(L, -3) );
  assert( lua_isboolean(L, -2) );
  (*matched) = lua_toboolean(L, -2);

  if (lua_istable(L, -1)) {
    rs = to_json_string(L, -1);
  }
  else if (lua_isstring(L, -1)) {
    byte_ptr temp_str;
    size_t temp_len;
    temp_str = (byte_ptr) lua_tolstring(L, -1, &(temp_len));
    rs = rosie_new_string_ptr(temp_str, temp_len);
  }
  else {
    LOG("trace() failed with unexpected return value from engine.trace()\n");
    LOGstack(L);
    lua_settop(L, 0);
    return ERR_ENGINE_CALL_FAILED;
  }

  (*trace).ptr = rs->ptr;
  (*trace).len = rs->len;

  lua_settop(L, 0);
  return SUCCESS;
}

/* N.B. Client must free 'errors' */
int rosie_load(lua_State *L, int *ok, str *src, str *pkgname, str *errors) {
  int t;
  size_t temp_len;
  unsigned char *temp_str;
  str *temp_rs;
  
  get_registry(engine_key);
  t = lua_getfield(L, -1, "load");
  CHECK_TYPE("engine.load()", t, LUA_TFUNCTION);
  lua_pushvalue(L, -2);		/* push engine object again */
  lua_pushlstring(L, (const char *)src->ptr, src->len);

  t = lua_pcall(L, 2, 3, 0); 
  if (t != LUA_OK) { 
    display("engine.load() failed"); 
    /* Details will likely not be helpful to the user */
    LOGstack(L);
    lua_settop(L, 0);
    return ERR_ENGINE_CALL_FAILED; 
  } 

  if (lua_isboolean(L, -3)) {
    *ok = lua_toboolean(L, -3);
    LOGf("engine.load() %s\n", ok ? "succeeded" : "failed");
  }
  
  if (lua_isstring(L, -2)) {
    temp_str = (unsigned char *)lua_tolstring(L, -2, &temp_len);
    *pkgname = rosie_new_string(temp_str, temp_len);
  }
  else {
    pkgname = NULL;
  }
  
  temp_rs = to_json_string(L, -1);
    if (temp_rs == NULL) {
      LOG("in load(), could not convert error information to json\n");
      lua_settop(L, 0);
      return ERR_ENGINE_CALL_FAILED;
    }
  errors->len = temp_rs->len;
  errors->ptr = temp_rs->ptr;

  lua_settop(L, 0);
  return SUCCESS;
}

/* N.B. Client must free 'errors' */
int rosie_import(lua_State *L, int *ok, str *pkgname, str *as, str *errors) {
  int t;
  size_t temp_len;
  unsigned char *temp_str;
  str *temp_rs;
  
  get_registry(engine_key);
  t = lua_getfield(L, -1, "import");
  CHECK_TYPE("engine.import()", t, LUA_TFUNCTION);
  lua_pushvalue(L, -2);		/* push engine object again */
  lua_pushlstring(L, (const char *)pkgname->ptr, pkgname->len);
  if (as) {
    lua_pushlstring(L, (const char *)as->ptr, as->len);
  }
  else {
    lua_pushnil(L);
  }

  t = lua_pcall(L, 3, 3, 0); 
  if (t != LUA_OK) { 
    LOG("engine.import() failed"); 
    LOGstack(L);
    lua_settop(L, 0);
    return ERR_ENGINE_CALL_FAILED; 
  } 

  *ok = lua_toboolean(L, -3);
  LOGf("engine.import() %s\n", ok ? "succeeded" : "failed");
  
  if (lua_isstring(L, -2)) {
    temp_str = (unsigned char *)lua_tolstring(L, -2, &temp_len);
    *pkgname = rosie_new_string(temp_str, temp_len);
    LOGf("engine.import reports that package %s was loaded\n", temp_str);
  }
  else {
    pkgname = NULL;
  }
  
  temp_rs = to_json_string(L, -1);
    if (temp_rs == NULL) {
      LOG("in import(), could not convert error information to json\n");
      lua_settop(L, 0);
      return ERR_ENGINE_CALL_FAILED;
    }
  errors->len = temp_rs->len;
  errors->ptr = temp_rs->ptr;

  lua_settop(L, 0);
  return SUCCESS;
}

/* FUTURE: Expose engine_process_file() */

/* TODO: Return SUCCESS and a failure indicator even when, e.g. file cannot be opened */
/* N.B. Client must free err */
int rosie_matchfile(lua_State *L, int pat, char *encoder, int wholefileflag,
		    char *infilename, char *outfilename, char *errfilename,
		    int *cin, int *cout, int *cerr,
		    str *err) {
  int t;
  unsigned char *temp_str;
  size_t temp_len;
  
  collect_if_needed(L);

  get_registry(engine_key);
  t = lua_getfield(L, -1, "matchfile");
  CHECK_TYPE("engine.matchfile()", t, LUA_TFUNCTION);
  get_registry(engine_key);	/* first arg */

  if (!pat)
    LOGf("rosie_matchfile() called with invalid compiled pattern reference: %d\n", pat);
  else {
    get_registry(rplx_table_key);
    t = lua_rawgeti(L, -1, pat); /* arg 2 */
    if (t == LUA_TTABLE) goto have_pattern;
  }
  (*cin) = -1;
  (*cout) = ERR_NO_PATTERN;
  lua_settop(L, 0);
  return SUCCESS;

have_pattern:

  lua_replace(L, -2); 		/* overwrite rplx table with rplx object */
  if (!encoder) {
    LOG("rosie_matchfile() called with null encoder arg\n");
    (*cin) = -1;
    (*cout) = ERR_NO_TRACESTYLE;
    lua_settop(L, 0);
    return SUCCESS;
  }

  lua_pushstring(L, infilename);  /* arg 3 */
  lua_pushstring(L, outfilename); /* arg 4 */
  lua_pushstring(L, errfilename); /* arg 5 */
  lua_pushstring(L, encoder);	  /* arg 6 */
  lua_pushboolean(L, wholefileflag); /* arg 7 */

  t = lua_pcall(L, 7, 3, 0); 
  if (t != LUA_OK) {  
    LOG("matchfile() failed\n");  
    LOGstack(L); 
    /* TODO: return the error! */
    lua_settop(L, 0); 
    return ERR_ENGINE_CALL_FAILED;  
  }  

  if (lua_isnil(L, -1)) {

       LOGstack(L);


       /* i/o issue with one of the files */
       (*cin) = -1;
       (*cout) = 3;
       temp_str =  (unsigned char *)lua_tolstring(L, -2, &temp_len);
       (*err) = rosie_new_string(temp_str, temp_len);
       lua_settop(L, 0);
       return SUCCESS;
  }

  (*cin) = lua_tointeger(L, -3);  /* cerr */
  (*cout) = lua_tointeger(L, -2); /* cout, or error code if error */
  (*cerr) = lua_tointeger(L, -1); /* cin, or -1 if error */
  (*err).ptr = NULL;
  (*err).len = 0;
  
  lua_settop(L, 0);
  return SUCCESS;
}


void rosie_finalize(void *L) {
  get_registry(prev_string_result_key); 
  if (lua_isuserdata(L, -1)) { 
    str *rs = lua_touserdata(L, -1); 
    rosie_free_string_ptr(rs); 
    lua_pop(L, 1); 
  } 
  LOGf("Finalizing engine %p\n", L);
  lua_close(L);
}

