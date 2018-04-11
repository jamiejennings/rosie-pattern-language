/*  -*- Mode: C; -*-                                                         */
/*                                                                           */
/* librosie.c    Expose the Rosie API                                        */
/*                                                                           */
/*  © Copyright IBM Corporation 2016, 2017                                   */
/*  LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)  */
/*  AUTHOR: Jamie A. Jennings                                                */

/* Protocol:
 * 
 * rosie_new() makes a new engine.  Every thread must have its own engine.
 * rosie_finalize() destroys an engine and frees its memory.
 *
 * Most functions have an argument 'str *messages':
 *
 * (1) If messages->ptr is NULL after the call, then there were no
 *     messages.
 * (2) If the return code from the call is non-zero, then the code
 *     will indicate the kind of error, and there MAY be a
 *     human-readable string explaining the error in messages.
 * (3) If the return code is zero, indicating success, there MAY be a
 *     JSON-encoded structure in messages.
 * (4) If messages->ptr is not NULL, then the caller must free
 *     messages when its value is no longer needed.
 *
*/

/* FUTURE: 
 * 
 * - MAYBE add a function that unloads all the dynamic libs, erases
 *   the global information about the libs, and reinitializes the
 *   ready_to_boot lock.
 * 
 *   - If a client unloads rosie, then the client's engines will
 *     become invalid.  Calling an engine function, even finalize(),
 *     will likely cause a crash.
 *
 *   - The responsibility to finalize all engines before unloading
 *     rosie will be left to the librosie client. 
 *
 *   - If the need to load/unload rosie at the dynamic library level
 *     arises, then someone can wrap librosie in a library that
 *     manages a pool of engines.
 */

#ifndef ROSIE_HOME
#error "ROSIE_HOME not defined (see Makefile for how it is typically set)"
#endif

#include <assert.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>

#include "librosie.h"

#include <dlfcn.h>
#include <libgen.h>

#define BOOTSCRIPT "/lib/boot.luac"

static char rosie_home[MAXPATHLEN];
static char bootscript[MAXPATHLEN];

#include "logging.c"
#include "registry.c"
#include "rosiestring.c"

/* Symbol visibility in the final library */
#define EXPORT __attribute__ ((visibility("default")))

/* ----------------------------------------------------------------------------------------
 * Locks
 * ----------------------------------------------------------------------------------------
 */

#define ACQUIRE_LOCK(lock) do {				                \
  int r = pthread_mutex_lock(&(lock));					\
  if (r) {								\
    fprintf(stderr, "%s:%d:%s(): pthread_mutex_lock failed with %d\n",	\
	    __FILE__, __LINE__, __func__, r);				\
    abort();								\
  }									\
} while (0)

#define RELEASE_LOCK(lock) do {				                \
  int r = pthread_mutex_unlock(&(lock));				\
  if (r) {								\
    fprintf(stderr, "%s:%d:%s(): pthread_mutex_unlock failed with %d\n", \
	    __FILE__, __LINE__, __func__, r);				\
    abort();								\
  }									\
} while (0)

/* ----------------------------------------------------------------------------------------
 * Engine locks
 * ----------------------------------------------------------------------------------------
 */

#define ACQUIRE_ENGINE_LOCK(e) ACQUIRE_LOCK((e)->lock)
#define RELEASE_ENGINE_LOCK(e) RELEASE_LOCK((e)->lock)

/* ----------------------------------------------------------------------------------------
 * Start-up / boot functions
 * ----------------------------------------------------------------------------------------
 */

static void set_bootscript() {
  size_t remaining;
  static char *last, *install_dir;
  static char *compile_time_path = (char *)ROSIE_HOME;
  static Dl_info info;
  /* 
   * Set rosie_home to ROSIE_HOME. A prefix of "//" means that it
   * should be relative to where librosie was found.
   */
  last = rosie_home;
  remaining = MAXPATHLEN;
  if (strncmp(compile_time_path, "//", (size_t) 2) == 0) {
    if (dladdr(&set_bootscript, &info) != 0) {
      install_dir = dirname(strndup(info.dli_fname, MAXPATHLEN));
      LOGf("install_dir = %s\n", install_dir);
      /* install_dir is where librosie.so is installed. */
      last = stpncpy(rosie_home, install_dir, remaining);
      *last = '\0';
      remaining = MAXPATHLEN - strnlen(rosie_home, MAXPATHLEN);
      compile_time_path++;		/* skip the first slash */
    }
  }
  last = stpncpy(last, compile_time_path, remaining);
  *last = '\0';
  remaining = MAXPATHLEN - strnlen(rosie_home, MAXPATHLEN);
  /* set absolute path to boot script */
  last = stpncpy(bootscript, rosie_home, remaining);
  remaining = MAXPATHLEN - strnlen(rosie_home, MAXPATHLEN);
  last = stpncpy(last, BOOTSCRIPT, remaining);
  *last = '\0';
  remaining = MAXPATHLEN - strnlen(rosie_home, MAXPATHLEN);
  assert(remaining > 0);
  LOGf("Bootscript filename set to %s\n", bootscript);
}

static int encoder_name_to_code(const char *name) {
  const r_encoder_t *entry = r_encoders;
  while (entry->name) {
    if (!strncmp(name, entry->name, MAX_ENCODER_NAME_LENGTH)) return entry->code;
    entry++;
  }
  return 0;
}

static pthread_once_t initialized = PTHREAD_ONCE_INIT;
static int all_is_lost = TRUE;

static void initialize() {
  LOG("INITIALIZE start\n");
  set_bootscript();
  all_is_lost = FALSE;
  LOG("INITIALIZE finish\n");
  return;
}

#define NO_INSTALLATION_MSG "unable to find rosie installation files"

static pthread_mutex_t booting = PTHREAD_MUTEX_INITIALIZER;

static int boot(lua_State *L, str *messages) {
  char *msg = NULL;
  if (!*bootscript) {
    *messages = rosie_new_string_from_const(NO_INSTALLATION_MSG);
    return FALSE;
  }
  LOGf("Booting rosie from %s\n", bootscript);
  ACQUIRE_LOCK(booting);

  int status = luaL_loadfile(L, bootscript);
  if (status != LUA_OK) {
    RELEASE_LOCK(booting);
    LOG("Failed to read rosie boot code (using loadfile)\n");
    if (asprintf(&msg, "no rosie installation in directory %s", rosie_home)) {
      *messages = rosie_string_from((byte_ptr) msg, strlen(msg));
    } else {
      *messages = rosie_new_string_from_const(NO_INSTALLATION_MSG);
    }
    return FALSE;
  }
  LOG("Reading of boot code succeeded (using loadfile)\n");
  status = lua_pcall(L, 0, LUA_MULTRET, 0);
  if (status != LUA_OK) {
    RELEASE_LOCK(booting);
    LOG("Loading of boot code failed\n");
    if (asprintf(&msg, "failed to load %s -- corrupt installation?", bootscript)) {
      *messages = rosie_string_from((byte_ptr) msg, strlen(msg));
    } else {
      *messages = rosie_new_string_from_const("loading of rosie boot code failed");
    }
    return FALSE;
  }
  LOG("Loading of boot code succeeded\n");
  lua_pushlstring(L, (const char *)rosie_home, strnlen(rosie_home, MAXPATHLEN));
  status = lua_pcall(L, 1, LUA_MULTRET, 0);
  if (status!=LUA_OK) {
    RELEASE_LOCK(booting);
    LOG("Boot function failed.  Lua stack is: \n");
    LOGstack(L);
    size_t len;
    const char *lua_msg = lua_tolstring(L, -1, &len);
    const char *intro = "execution of rosie boot loader failed:\n";
    char *msg = malloc(strlen(intro) + strnlen(lua_msg, 1000) + 1);
    char *last = stpcpy(msg, intro);
    stpncpy(last, lua_msg, 1000-strlen(intro));
    *messages = rosie_string_from((unsigned char *)msg, len+strlen(intro));
    return FALSE;
  }
  RELEASE_LOCK(booting);
  LOG("Boot function succeeded\n");
  return TRUE;
}

static int to_json_string(lua_State *L, int pos, str *json_string) {
     size_t len;
     byte_ptr str;
     int t;
     int top = lua_gettop(L);
     get_registry(json_encoder_key);
     lua_pushvalue(L, pos-1);                /* offset because we pushed json_encoder */
     if (!lua_istable(L, -1)) return ERR_SYSCALL_FAILED;
     *json_string = rosie_string_from(NULL, 0);
     /* When the messages table is empty, be sure to return a null rosie_string */
     lua_pushnil(L);
     if (!lua_next(L, pos-1)) {
       return LUA_OK;
     } else {
       lua_pop(L, 2);
     }
     t = lua_pcall(L, 1, LUA_MULTRET, 0);
     if (t != LUA_OK) {
       LOG("call to json encoder failed\n"); /* more detail may not be useful to the user */
       LOGstack(L);
       return ERR_SYSCALL_FAILED;
     }
     if ((lua_gettop(L) - top) > 1) {
       /* Top of stack is error msg */
       LOG("call to json encoder returned more than one value\n");
       if (lua_isstring(L, -1) && lua_isnil(L, -2)) {
	 LOGf("error message from json encoder: %s\n", lua_tolstring(L, -1, NULL));
	 LOGstack(L);
	 return ERR_SYSCALL_FAILED;
       }
       else {
	 /* Something really strange happened!  Is there any useful info to return? */
	 LOG("call to json encoder returned unexpected values\n");
	 LOGstack(L);
	 return ERR_SYSCALL_FAILED;
       }
     }
     str = (byte_ptr) lua_tolstring(L, -1, &len);
     *json_string = rosie_new_string(str, len);
     return LUA_OK;
}

static int format_violation_messages(lua_State *L) {
  int t;

  get_registry(violation_format_key);

  /* Now have this stack: format_each(), messages[], ...
     And violation.format_each() mutates its argument.
  */
  lua_pushvalue(L, -2);		/* push copy of messages table */
  t = lua_pcall(L, 1, 1, 0);	/* violation.format_each() */
  if (t != LUA_OK) { 
    LOG("violation.format_each() failed\n"); 
    LOGstack(L);
    return ERR_ENGINE_CALL_FAILED; 
  } 
  return LUA_OK;
}

static int violations_to_json_string(lua_State *L, str *json_string) {
  CHECK_TYPE("violation messages", lua_type(L, -1), LUA_TTABLE);
  int t = format_violation_messages(L);
  LOGstack(L);
  if (t == LUA_OK) {
    t = to_json_string(L, -1, json_string);
    if (t != LUA_OK) LOG("could not convert violations to json\n");
  }
  return t;
} 

int luaopen_lpeg (lua_State *L);
int luaopen_cjson_safe(lua_State *l);

static lua_State *newstate() {
  lua_State *newL = luaL_newstate();
  luaL_checkversion(newL); /* Ensures several critical things needed to use Lua */
  luaL_openlibs(newL);     /* Open lua's standard libraries */
  luaL_requiref(newL, "lpeg", luaopen_lpeg, 0);
  luaL_requiref(newL, "cjson.safe", luaopen_cjson_safe, 0);
  return newL;
}
  

/* ----------------------------------------------------------------------------------------
 * Exported functions
 * ----------------------------------------------------------------------------------------
 */

EXPORT
Engine *rosie_new(str *messages) {

  pthread_once(&initialized, initialize);
  if (all_is_lost) {
    *messages = rosie_new_string_from_const("initialization failed; enable DEBUG output for details");
    return NULL;
  }

  int t;
  Engine *e = malloc(sizeof(Engine));
  lua_State *L = newstate();
  if (L == NULL) {
    *messages = rosie_new_string_from_const("not enough memory to initialize");
    return NULL;
  }

  if (!boot(L, messages)) {
    return NULL;		/* messages already set by boot */
  }
  if (!lua_checkstack(L, 6)) {
    LOG("Cannot initialize: not enough memory for stack\n");
    *messages = rosie_new_string_from_const("not enough memory for stack");
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
    LOG("rosie.engine.new() failed\n");
    *messages = rosie_new_string_from_const("rosie.engine.new() failed");
    return NULL;
  }

  /* Engine instance is at top of stack */
  set_registry(engine_key);
  t = lua_getfield(L, -1, "match");
  CHECK_TYPE("engine.match", t, LUA_TFUNCTION);
  set_registry(engine_match_key);

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

  lua_getglobal(L, "rosie");
  t = lua_getfield(L, -1, "env");
  CHECK_TYPE("rosie.env", t, LUA_TTABLE);
  t = lua_getfield(L, -1, "violation");
  CHECK_TYPE("rosie.env.violation", t, LUA_TTABLE);
  t = lua_getfield(L, -1, "format_each");
  CHECK_TYPE("rosie.env.violation.format_each", t, LUA_TFUNCTION);
  set_registry(violation_format_key);

  lua_pushinteger(L, 0);
  set_registry(alloc_set_limit_key);

  pthread_mutex_init(&(e->lock), NULL);
  e->L = L;

  lua_settop(L, 0);
  LOGf("Engine %p created\n", e);
  return e;
}
     
/* newlimit of -1 means query for current limit */
EXPORT
int rosie_alloc_limit (Engine *e, int *newlimit, int *usage) {
  int memusg, actual_limit;
  lua_State *L = e->L;
  LOGf("rosie_alloc_limit() called with int pointers %p, %p\n", newlimit, usage);
  ACQUIRE_ENGINE_LOCK(e);
  lua_gc(L, LUA_GCCOLLECT, 0);
  lua_gc(L, LUA_GCCOLLECT, 0);        /* second time to free resources marked for finalization */
  memusg = lua_gc(L, LUA_GCCOUNT, 0); /* KB */
  if (usage) *usage = memusg;
  if (newlimit) {
    int limit = *newlimit;
    if ((limit != -1) && (limit != 0) && (limit < MIN_ALLOC_LIMIT_MB)) {
      RELEASE_ENGINE_LOCK(e);
      return ERR_ENGINE_CALL_FAILED;
    } 
    if (limit == -1) {
      /* query */
      get_registry(alloc_set_limit_key);
      *newlimit = lua_tointeger(L, -1);
    } else {
      /* set new limit */
      lua_pushinteger(L, limit);
      set_registry(alloc_set_limit_key);
      actual_limit = memusg + limit;
      lua_pushinteger(L, (limit == 0) ? 0 : actual_limit);
      set_registry(alloc_actual_limit_key);
      if (limit == 0) {
	LOGf("set alloc limit to UNLIMITED above current usage level of %0.1f MB\n", memusg/1024.0);
      } else {
	LOGf("set alloc limit to %d MB above current usage level of %0.1f MB\n", *newlimit, memusg/1024.0);
      }
    }
  }
  lua_settop(L, 0);
  RELEASE_ENGINE_LOCK(e);
  return SUCCESS;
}

/* N.B. Client must free retval */
EXPORT
int rosie_config(Engine *e, str *retval) {
  int t;
  str r;
  lua_State *L = e->L;
  ACQUIRE_ENGINE_LOCK(e);
  get_registry(rosie_key);
  t = lua_getfield(L, -1, "config");
  CHECK_TYPE("config", t, LUA_TFUNCTION);
  get_registry(engine_key);
  t = lua_pcall(L, 1, 1, 0);
  if (t != LUA_OK) {
    LOG("rosie.config() failed\n");
    *retval = rosie_new_string_from_const("rosie.config() failed");
    lua_settop(L, 0);
    RELEASE_ENGINE_LOCK(e);
    return ERR_ENGINE_CALL_FAILED;
  }
  t = to_json_string(L, -1, &r);
  if (t != LUA_OK) {
    LOGf("in config(), could not convert config information to json (code=%d)\n", t);
    *retval = rosie_new_string_from_const("in config(), could not convert config information to json");
    lua_settop(L, 0);
    RELEASE_ENGINE_LOCK(e);
    return ERR_ENGINE_CALL_FAILED;
  }
  retval->len = r.len;
  retval->ptr = r.ptr;
  lua_settop(L, 0);
  RELEASE_ENGINE_LOCK(e);
  return SUCCESS;
}

EXPORT
int rosie_libpath(Engine *e, str *newpath) {
  int t;
  lua_State *L = e->L;
  ACQUIRE_ENGINE_LOCK(e);
  get_registry(engine_key);
  if (newpath->ptr) {
    t = lua_getfield(L, -1, "set_libpath");
    CHECK_TYPE("engine.set_libpath()", t, LUA_TFUNCTION);
  } else {
    t = lua_getfield(L, -1, "get_libpath");
    CHECK_TYPE("engine.get_libpath()", t, LUA_TFUNCTION);
  }    
  lua_pushvalue(L, -2);
  if (newpath->ptr) {
    lua_pushlstring(L, (const char *)newpath->ptr, newpath->len);
    lua_pushstring(L, "API");
  }
  t = lua_pcall(L, (newpath->ptr) ? 3 : 1, (newpath->ptr) ? 0 : 2, 0);
  if (t != LUA_OK) {
    if (newpath->ptr) {
	LOG("engine.set_libpath() failed\n");
      } else {
	LOG("engine.get_libpath() failed\n");
    }      
    lua_settop(L, 0);
    RELEASE_ENGINE_LOCK(e);
    return ERR_ENGINE_CALL_FAILED;
  }
#if LOGGING
  do {
    get_registry(engine_key);
    t = lua_getfield(L, -1, "libpath");
    t = lua_getfield(L, -1, "value");
    LOGf("libpath obtained directly from engine object is: %s\n", lua_tostring(L, -1));
    lua_pop(L, 3);
  } while (0);
#endif
  if (!newpath->ptr) {
    size_t tmplen;
    const char *tmpptr = lua_tolstring(L, -2, &tmplen);
    str tmpstr = rosie_new_string((byte_ptr)tmpptr, tmplen);
    (*newpath).ptr = tmpstr.ptr;
    (*newpath).len = tmpstr.len;
  }
  lua_settop(L, 0);
  RELEASE_ENGINE_LOCK(e);
  return SUCCESS;
}

/* GC in languages like Python 3 may collect the engine before the
   rplx objects, so if we cannot obtain the engine lock due to an
   error (as opposed to the lock being held), then we assume the
   engine has been collected and there is nothing that free_rplx needs
   to do.
 */
EXPORT
int rosie_free_rplx (Engine *e, int pat) {
  lua_State *L = e->L;
  LOGf("freeing rplx object with index %d\n", pat);
  int r = pthread_mutex_lock(&((e)->lock));
  if (!r) {
    get_registry(rplx_table_key);
    luaL_unref(L, -1, pat);
    lua_settop(L, 0);
    RELEASE_ENGINE_LOCK(e);
  }
  return SUCCESS;
}

/* N.B. Client must free messages */
EXPORT
int rosie_compile(Engine *e, str *expression, int *pat, str *messages) {
  int t;
  str temp_rs;
  lua_State *L = e->L;
  
  *pat = 0;
  if (!expression) {
    LOG("null pointer passed to compile for expression argument\n");
    return ERR_ENGINE_CALL_FAILED;
  }  

  LOGf("compile(): L = %p, expression = %*s\n", L, expression->len, expression->ptr);
  ACQUIRE_ENGINE_LOCK(e);
  if (!pat) {
    LOG("null pointer passed to compile for pattern argument\n");
    lua_settop(L, 0);
    RELEASE_ENGINE_LOCK(e);
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
    LOG("compile() failed\n");
    LOGstack(L);
    lua_settop(L, 0);
    RELEASE_ENGINE_LOCK(e);
    return ERR_ENGINE_CALL_FAILED;
  }

  if ( !lua_toboolean(L, -2) ) {
    *pat = 0;
    t = violations_to_json_string(L, &temp_rs);
    if (t != LUA_OK) {
      lua_settop(L, 0);
      RELEASE_ENGINE_LOCK(e);
      *messages = rosie_new_string_from_const("could not convert compile messages to json");
      return ERR_ENGINE_CALL_FAILED;
    }
    (*messages).ptr = temp_rs.ptr;
    (*messages).len = temp_rs.len;
    lua_settop(L, 0);
    RELEASE_ENGINE_LOCK(e);
    return SUCCESS;
  }
  
  lua_pushvalue(L, -2);
  CHECK_TYPE("new rplx object", lua_type(L, -1), LUA_TTABLE);
  *pat = luaL_ref(L, 1);
  if (*pat == LUA_REFNIL) {
    LOG("error storing rplx object\n");
    LOGstack(L);
    lua_settop(L, 0);
    RELEASE_ENGINE_LOCK(e);
    return ERR_ENGINE_CALL_FAILED;
  }
  LOGf("storing rplx object at index %d\n", *pat);

  t = violations_to_json_string(L, &temp_rs);
  if (t != LUA_OK) {
    LOG("in compile(), could not convert warning information to json\n");
    lua_settop(L, 0);
    RELEASE_ENGINE_LOCK(e);
    return ERR_ENGINE_CALL_FAILED;
  }
  
  (*messages).ptr = temp_rs.ptr;
  (*messages).len = temp_rs.len;

  lua_settop(L, 0);
  RELEASE_ENGINE_LOCK(e);
  return SUCCESS;
}

static inline void collect_if_needed(lua_State *L) {
  int limit, memusg;
  get_registry(alloc_actual_limit_key);
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

EXPORT
int rosie_match(Engine *e, int pat, int start, char *encoder_name, str *input, match *match) {
  int t, encoder, result_type, match_code;
  size_t temp_len;
  unsigned char *temp_str;
  rBuffer *buf;
  lua_State *L = e->L;
  LOG("rosie_match called\n");
  ACQUIRE_ENGINE_LOCK(e);
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
  RELEASE_ENGINE_LOCK(e);
  return SUCCESS;

have_pattern:

  /* The encoder values that do not require Lua processing have
   * non-zero codes, and take a different code path from the ones that
   * do.  When no Lua processing is needed, we can (1) use a
   * lightuserdata to hold a ptr to the rosie_string holding the
   * input, and (2) call into a refactored rmatch that expects this.
   *
   * Otherwise, we call the lua function rplx.Cmatch().
   */

  encoder = encoder_name_to_code(encoder_name);
  LOGf("in rosie_match, encoder value is %d\n", encoder);
  if (!encoder) {
    /* Path through Lua */
    t = lua_getfield(L, -1, "Cmatch");
    CHECK_TYPE("rplx.Cmatch()", t, LUA_TFUNCTION);
    /* FUTURE: Cache Cmatch, because it is constant across all rplx
     * objects created by this engine.  Should move it out of rplx
     * object and into engine module, then create a registry key for
     * it, which we can retrieve here.
     */
    lua_replace(L, 1);
    lua_settop(L, 2);
    /* Don't make a copy of the input.  Wrap it in an rbuf, which will
       be gc'd later (but will not free the original source data). */
    r_newbuffer_wrap(L, (char *)input->ptr, input->len); 
    lua_pushinteger(L, start);
    lua_pushstring(L, encoder_name);
    assert(lua_gettop(L) == 5);
  }
  else {
    /* Path through C */

    /* FUTURE: Store two arrays, one for the rplx object (like now)
     * and one for the peg.  Retrieve only the peg here.
     */
    t = lua_getfield(L, -1, "pattern");
    CHECK_TYPE("rplx pattern slot", t, LUA_TTABLE);
    t = lua_getfield(L, -1, "peg");
    CHECK_TYPE("rplx pattern peg slot", t, LUA_TUSERDATA);
    lua_pushcfunction(L, r_match_C);
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
    RELEASE_ENGINE_LOCK(e);
    return ERR_ENGINE_CALL_FAILED;  
  }  

  (*match).tmatch = lua_tointeger(L, -1);
  (*match).ttotal = lua_tointeger(L, -2);
  (*match).abend = lua_toboolean(L, -3);
  (*match).leftover = lua_tointeger(L, -4);
  lua_pop(L, 4);

  result_type = lua_type(L, -1);
  switch (result_type) {
  case LUA_TUSERDATA: {
    buf = lua_touserdata(L, -1);
    LOG("in rosie_match, match succeeded\n");
    (*match).data.ptr = (unsigned char *)buf->data;
    (*match).data.len = buf->n;
    break;
  }
  case LUA_TNUMBER: {
    match_code = lua_tointeger(L, -1);
    LOGf("in rosie_match, match returned the integer code %d\n", match_code);
    set_match_error(match, match_code);
    break;
  }
  case LUA_TSTRING: {
    if (encoder) {
      LOG("Invalid return type from rmatch (string)\n");
      match = NULL;
      lua_settop(L, 0);
      RELEASE_ENGINE_LOCK(e);
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
    str *rs = lua_touserdata(L, -1);
    if (rs) rosie_free_string_ptr(rs);
    lua_pop(L, 1);
    temp_str = (unsigned char *)lua_tolstring(L, -1, &temp_len);
    rs = rosie_new_string_ptr(temp_str, temp_len);
    lua_pushlightuserdata(L, (void *) rs);
    set_registry(prev_string_result_key);
    (*match).data.ptr = rs->ptr;
    (*match).data.len = rs->len;
    break;
  }
  default: {
    t = lua_type(L, -1);
    LOGf("Invalid return type from rmatch (%d)\n", t);
    match = NULL;
    lua_settop(L, 0);
    RELEASE_ENGINE_LOCK(e);
    return ERR_ENGINE_CALL_FAILED;
  } }

  lua_settop(L, 0);
  RELEASE_ENGINE_LOCK(e);
  return SUCCESS;
}

/* N.B. Client must free trace */
EXPORT
int rosie_trace(Engine *e, int pat, int start, char *trace_style, str *input, int *matched, str *trace) {
  int t;
  str rs;
  lua_State *L = e->L;
  ACQUIRE_ENGINE_LOCK(e);
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
  RELEASE_ENGINE_LOCK(e);
  return SUCCESS;

have_pattern:

  lua_replace(L, -2); 		/* overwrite rplx table with rplx object */
  if (!trace_style) {
    LOG("rosie_trace() called with null trace_style arg\n");
    (*trace).ptr = NULL;
    (*trace).len = ERR_NO_ENCODER;
    lua_settop(L, 0);
    RELEASE_ENGINE_LOCK(e);
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
    RELEASE_ENGINE_LOCK(e);
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
    t = to_json_string(L, -1, &rs);
    if (t != LUA_OK) {
      rs = rosie_new_string_from_const("error: could not convert trace data to json");      
      goto fail_with_message;
    }
  }
  else if (lua_isstring(L, -1)) {
    byte_ptr temp_str;
    size_t temp_len;
    temp_str = (byte_ptr) lua_tolstring(L, -1, &(temp_len));
    rs = rosie_new_string(temp_str, temp_len);
  }
  else {
    LOG("trace() failed with unexpected return value from engine.trace()\n");
    LOGstack(L);
    lua_settop(L, 0);
    RELEASE_ENGINE_LOCK(e);
    return ERR_ENGINE_CALL_FAILED;
  }

 fail_with_message:
  
  (*trace).ptr = rs.ptr;
  (*trace).len = rs.len;

  lua_settop(L, 0);
  RELEASE_ENGINE_LOCK(e);
  return SUCCESS;
}

/* N.B. Client must free 'messages' */
EXPORT
int rosie_load(Engine *e, int *ok, str *src, str *pkgname, str *messages) {
  int t;
  size_t temp_len;
  unsigned char *temp_str;
  str temp_rs;
  lua_State *L = e->L;
  ACQUIRE_ENGINE_LOCK(e);
  get_registry(engine_key);
  t = lua_getfield(L, -1, "load");
  CHECK_TYPE("engine.load()", t, LUA_TFUNCTION);
  lua_pushvalue(L, -2);		/* push engine object again */
  lua_pushlstring(L, (const char *)src->ptr, src->len);

  t = lua_pcall(L, 2, 3, 0); 
  if (t != LUA_OK) { 
    /* Details will likely not be helpful to the user */
    LOG("engine.load() failed\n"); 
    *messages = rosie_new_string_from_const("engine.load() failed"); 
    LOGstack(L);
    lua_settop(L, 0);
    RELEASE_ENGINE_LOCK(e);
    return ERR_ENGINE_CALL_FAILED; 
  } 

  *ok = lua_toboolean(L, -3);
  LOGf("engine.load() %s\n", *ok ? "succeeded\n" : "failed\n");
  
  if (lua_isstring(L, -2)) {
    temp_str = (unsigned char *)lua_tolstring(L, -2, &temp_len);
    *pkgname = rosie_new_string(temp_str, temp_len);
  }
  else {
    pkgname->ptr = NULL;
    pkgname->len = 0;
  }
  
  t = violations_to_json_string(L, &temp_rs);
  if (t != LUA_OK) {
    LOG("in load(), could not convert error information to json\n");
    temp_rs = rosie_new_string_from_const("in load(), could not convert error information to json");
    goto fail_load_with_messages;
    }

 fail_load_with_messages:
  (*messages).ptr = temp_rs.ptr;
  (*messages).len = temp_rs.len;

  lua_settop(L, 0);
  RELEASE_ENGINE_LOCK(e);
  return SUCCESS;
}

/* N.B. Client must free 'messages' */
EXPORT
int rosie_loadfile(Engine *e, int *ok, str *fn, str *pkgname, str *messages) {
  int t;
  size_t temp_len;
  unsigned char *temp_str;
  str temp_rs;
  lua_State *L = e->L;
  ACQUIRE_ENGINE_LOCK(e);
  get_registry(engine_key);
  t = lua_getfield(L, -1, "loadfile");
  CHECK_TYPE("engine.loadfile()", t, LUA_TFUNCTION);
  lua_pushvalue(L, -2);		/* push engine object again */
  const char *fname = lua_pushlstring(L, (const char *)fn->ptr, fn->len);

  LOGf("engine.loadfile(): about to load %s\n", fname);
  t = lua_pcall(L, 2, 3, 0); 
  if (t != LUA_OK) { 
    display("Internal error: call to engine.loadfile() failed"); 
    /* Details will likely not be helpful to the user */
    LOGstack(L);
    lua_settop(L, 0);
    RELEASE_ENGINE_LOCK(e);
    return ERR_ENGINE_CALL_FAILED; 
  } 

  *ok = lua_toboolean(L, -3);
  LOGf("engine.loadfile() %s\n", *ok ? "succeeded" : "failed");
  LOGstack(L);
  
  if (lua_isstring(L, -2)) {
    temp_str = (unsigned char *)lua_tolstring(L, -2, &temp_len);
    str loaded_pkgname = rosie_new_string(temp_str, temp_len);
    (*pkgname).ptr = loaded_pkgname.ptr;
    (*pkgname).len = loaded_pkgname.len;
  }
  else {
    (*pkgname).ptr = NULL;
    (*pkgname).len = 0;
  }
  
  t = violations_to_json_string(L, &temp_rs);
  if (t != LUA_OK) {
    LOG("in load(), could not convert error information to json\n");
    lua_settop(L, 0);
    RELEASE_ENGINE_LOCK(e);
    return ERR_ENGINE_CALL_FAILED;
  }
  (*messages).ptr = temp_rs.ptr;
  (*messages).len = temp_rs.len;

  lua_settop(L, 0);
  RELEASE_ENGINE_LOCK(e);
  return SUCCESS;
}

/* N.B. Client must free 'messages' */
EXPORT
int rosie_import(Engine *e, int *ok, str *pkgname, str *as, str *actual_pkgname, str *messages) {
  int t;
  size_t temp_len;
  unsigned char *temp_str;
  str temp_rs;
  lua_State *L = e->L;
  
  ACQUIRE_ENGINE_LOCK(e);
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
    LOG("engine.import() failed\n"); 
    LOGstack(L);
    lua_settop(L, 0);
    RELEASE_ENGINE_LOCK(e);
    return ERR_ENGINE_CALL_FAILED; 
  } 

  *ok = lua_toboolean(L, -3);
  LOGf("import %*s %s\n", pkgname->len, pkgname->ptr, *ok ? "succeeded" : "failed");
  
  if (lua_isstring(L, -2)) {
    temp_str = (unsigned char *)lua_tolstring(L, -2, &temp_len);
    *actual_pkgname = rosie_new_string(temp_str, temp_len);
    LOGf("engine.import reports that package %s was loaded\n", temp_str);
  }
  else {
    (*actual_pkgname).ptr = NULL;
    (*actual_pkgname).len = 0;
  }
  
  t = violations_to_json_string(L, &temp_rs);
  if (t != LUA_OK) {
    LOG("could not convert error information to json\n");
    lua_settop(L, 0);
    RELEASE_ENGINE_LOCK(e);
    return ERR_ENGINE_CALL_FAILED;
  }
  (*messages).ptr = temp_rs.ptr;
  (*messages).len = temp_rs.len;

  lua_settop(L, 0);
  RELEASE_ENGINE_LOCK(e);
  return SUCCESS;
}

/* FUTURE: Expose engine_process_file() ? */

/* N.B. Client must free err */
EXPORT
int rosie_matchfile(Engine *e, int pat, char *encoder, int wholefileflag,
		    char *infilename, char *outfilename, char *errfilename,
		    int *cin, int *cout, int *cerr,
		    str *err) {
  int t;
  unsigned char *temp_str;
  size_t temp_len;
  lua_State *L = e->L;
  (*err).ptr = NULL;
  (*err).len = 0;

  ACQUIRE_ENGINE_LOCK(e);
  collect_if_needed(L);
  get_registry(engine_key);
  t = lua_getfield(L, -1, "matchfile");
  CHECK_TYPE("engine.matchfile()", t, LUA_TFUNCTION);
  get_registry(engine_key);	/* first arg */

  get_registry(rplx_table_key);
  t = lua_rawgeti(L, -1, pat); /* arg 2 */
  if (t != LUA_TTABLE) {
    LOGf("rosie_matchfile() called with invalid compiled pattern reference: %d\n", pat);
    (*cin) = -1;
    (*cout) = ERR_NO_PATTERN;
    lua_settop(L, 0);
    RELEASE_ENGINE_LOCK(e);
    return SUCCESS;
  }

  lua_replace(L, -2); 		/* overwrite rplx table with rplx object */
  if (!encoder) {
    LOG("rosie_matchfile() called with null encoder name\n");
    (*cin) = -1;
    (*cout) = ERR_NO_ENCODER;
    lua_settop(L, 0);
    RELEASE_ENGINE_LOCK(e);
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
    /* FUTURE: return the error, if there's a situation where it may help */
    lua_settop(L, 0); 
    RELEASE_ENGINE_LOCK(e);
    return ERR_ENGINE_CALL_FAILED;  
  }  

  if (lua_isnil(L, -1)) {

       LOGstack(L);

       /* i/o issue with one of the files */
       (*cin) = -1;
       (*cout) = 3;
       temp_str =  (unsigned char *)lua_tolstring(L, -2, &temp_len);
       str msg = rosie_new_string(temp_str, temp_len);
       (*err).ptr = msg.ptr;
       (*err).len = msg.len;
       lua_settop(L, 0);
       RELEASE_ENGINE_LOCK(e);
       return SUCCESS;
  }

  (*cin) = lua_tointeger(L, -3);  /* cerr */
  (*cout) = lua_tointeger(L, -2); /* cout, or error code if error */
  (*cerr) = lua_tointeger(L, -1); /* cin, or -1 if error */
  
  lua_settop(L, 0);
  RELEASE_ENGINE_LOCK(e);
  return SUCCESS;
}

static int push_rcfile_args(Engine *e, str *filename) {
  lua_State *L = e->L;		/* for the CHECK_TYPE macro */
  int is_default_rcfile = (filename->ptr == NULL);
  /* Push engine */
  get_registry(engine_key);
  /* Push filename */
  if (!filename->ptr) {
    /* Use default rc filename */
    LOG("using default rc filename\n");
    get_registry(rosie_key);	/* stack: rosie, engine, read_rcfile, rosie */
    lua_getfield(L, -1, "default");	/* stack: default, rosie, engine, read_rcfile, rosie */
    CHECK_TYPE("default", t, LUA_TTABLE);
    lua_remove(L, -2); /* stack: default, engine, read_rcfile, rosie */
    lua_getfield(L, -1, "rcfile"); /* stack: rcfile, default, engine, read_rcfile, rosie */
    CHECK_TYPE("rcfile", t, LUA_TSTRING);
    lua_remove(L, -2); /* stack: rcfile, engine, read_rcfile, rosie */
    /* stack: rcfile, engine, read_rcfile, rosie */
  } else {
    LOGf("using supplied rc filename: %*s\n",
	 filename->len, filename->ptr);
    is_default_rcfile = FALSE;
    lua_pushlstring(L, (const char *)filename->ptr, filename->len);
    /* stack: filename, rcfile, engine, read_rcfile, rosie */
  }
  /* Push engine maker */
  get_registry(rosie_key);
  lua_getfield(L, -1, "engine");
  CHECK_TYPE("engine", t, LUA_TTABLE);
  /* stack: engine, rosie, rcfile, engine, read_rcfile, rosie */
  lua_remove(L, -2); /* stack: engine, rcfile, engine, read_rcfile, rosie */
  lua_getfield(L, -1, "new");
  CHECK_TYPE("engine.new", t, LUA_TFUNCTION);
  /* stack: engine_maker, engine, rcfile, engine, read_rcfile, rosie */
  lua_remove(L, -2); /* stack: engine_maker, rcfile, engine, read_rcfile, rosie */
  /* Push is_default_rcfile */
  lua_pushboolean(L, is_default_rcfile);
  return LUA_OK;
}

/* N.B. Client must free options */
EXPORT
int rosie_read_rcfile(Engine *e, str *filename, int *file_exists, str *options, str *messages) {
  str r;
  int t;
  ACQUIRE_ENGINE_LOCK(e);
  lua_State *L = e->L;
  get_registry(engine_key);
  t = lua_getfield(L, -1, "read_rcfile");
  CHECK_TYPE("read_rcfile", t, LUA_TFUNCTION);
  /* Push all the args */
  t = push_rcfile_args(e, filename);
  if (t != LUA_OK) goto read_rcfile_failed;
  t = lua_pcall(L, 4, 3, 0);
  if (t != LUA_OK) {
    LOG("read_rcfile() failed\n");
    LOGstack(L);
    *options = rosie_new_string_from_const("read_rcfile() failed");
    goto read_rcfile_failed;
  }
  /* return values are file_existed (bool), options_table (or false), messages (or nil) */
  *file_exists = lua_toboolean(L, -3);
  if (*file_exists) {
    LOG("rc file exists\n");
  } else {
    LOG("rc file does not exist\n");
  }
  if (lua_istable(L, -2)) {
    LOG("file processed successfully\n");
    t = to_json_string(L, -2, &r);
    if (t == LUA_OK) {
      options->len = r.len;
      options->ptr = r.ptr;
    } else {
      LOGf("could not convert options to json (code=%d)\n", t);
      LOGstack(L);
      *options = rosie_new_string_from_const("in read_rcfile(), could not convert options to json");
      goto read_rcfile_failed;
    }
  } else {
    LOG("file FAILED to process without errors\n");
  }
  if (lua_istable(L, -1)) {
    LOG("there are messages\n");
    t = to_json_string(L, -1, &r);
    if (t == LUA_OK) {
      messages->len = r.len;
      messages->ptr = r.ptr;
    } else {
      LOG("could not convert messages to json\n");
      *messages = rosie_new_string_from_const("error: could not convert messages to json");      
    }
  } else {
    LOG("there were no messages\n");
  }
  lua_settop(L, 0);
  RELEASE_ENGINE_LOCK(e);
  return SUCCESS;

 read_rcfile_failed:
  lua_settop(L, 0);
  RELEASE_ENGINE_LOCK(e);
  return ERR_ENGINE_CALL_FAILED;
}

/* N.B. Client must free options */
EXPORT
int rosie_execute_rcfile(Engine *e, str *filename, int *file_exists, int *no_errors, str *messages) {
  int t;
  str r;
  ACQUIRE_ENGINE_LOCK(e);
  lua_State *L = e->L;
  get_registry(engine_key);
  t = lua_getfield(L, -1, "execute_rcfile");
  CHECK_TYPE("execute_rcfile", t, LUA_TFUNCTION);
  /* Push all but the last arg */
  t = push_rcfile_args(e, filename);
  if (t != LUA_OK) goto execute_rcfile_failed;
  /* Push the set_by arg */
  lua_pushstring(L, "API");
  t = lua_pcall(L, 5, 3, 0);
  if (t != LUA_OK) {
  execute_rcfile_failed:
    LOG("execute_rcfile() failed\n");
    LOGstack(L);
    lua_settop(L, 0);
    RELEASE_ENGINE_LOCK(e);
    return ERR_ENGINE_CALL_FAILED;
  }
  /* return values are file_existed, processed_without_error, messages */
  *file_exists = lua_toboolean(L, -3);
  *no_errors = FALSE;
  if (*file_exists) {
    LOG("rc file exists\n");
  } else {
    LOG("rc file does not exist\n");
  }
  if (lua_toboolean(L, -2)) {
    LOG("rc file processed successfully\n");
    *no_errors = TRUE;
  }
  else {
    LOG("file FAILED to process without errors\n");
  }
  if (lua_istable(L, -1)) {
    LOG("there are messages\n");
    t = to_json_string(L, -1, &r);
    if (t == LUA_OK) {
      messages->len = r.len;
      messages->ptr = r.ptr;
    } else {
      LOG("could not convert messages to json\n");
      *messages = rosie_new_string_from_const("error: could not convert messages to json");      
      goto execute_rcfile_failed;
    }
  } else {
    LOG("there were no messages\n");
  }
  lua_settop(L, 0);
  RELEASE_ENGINE_LOCK(e);
  return SUCCESS;
}

EXPORT
void rosie_finalize(Engine *e) {
  lua_State *L = e->L;
  ACQUIRE_ENGINE_LOCK(e);
  get_registry(prev_string_result_key); 
  if (lua_isuserdata(L, -1)) { 
    str *rs = lua_touserdata(L, -1); 
    if (rs->ptr) rosie_free_string_ptr(rs); 
    lua_pop(L, 1); 
  } 
  LOGf("Finalizing engine %p\n", L);
  lua_close(L);
  /*
   * We do not RELEASE_ENGINE_LOCK(e) here because a waiting thread
   * would then have access to an engine which we have closed, and
   * whose memory we are about to free.
   *
   * The caller should take care to have each engine be created, used,
   * destroyed, and then never used again.  
   *
   * One way to achieve this is to have each thread responsible for
   * creating and destroying its own engines.  In that scenario, a
   * thread's engine should be private to that thread.
   * 
   * Alternatively, an engine pool could be created (in the client
   * code).  The pool manager would be responsible for calling
   * rosie_finalize() when there is no danger of any thread attempting
   * to use the engine being destroyed.
   *
   */
  free(e);
}

