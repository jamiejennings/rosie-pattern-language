/*  -*- Mode: C/l; -*-                                                       */
/*                                                                           */
/*  librosiecli.c                                                            */
/*                                                                           */
/*  © Copyright IBM 2018.                                                    */
/*  LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)  */
/*  AUTHOR: Jamie A. Jennings                                                */


#define CLI_LUAC "/lib/cli.luac"


#include "librosie.c"		/* This may be problematic */
#include "lua_repl.h"


/* ----------------------------------------------------------------------------------------
 * Functions to support the Lua implementation of the CLI
 * ----------------------------------------------------------------------------------------
 */

static void pushargs(lua_State *L, int argc, char **argv) {
  lua_createtable(L, argc+1, 0);
  for (int i = 0; i < argc; i++) {
    lua_pushstring(L, argv[i]);
    lua_rawseti(L, -2, i);
  }
  lua_setglobal(L, "arg");
}

int luaopen_readline (lua_State *L); /* will dynamically load the system libreadline/libedit */

static int rosie_exec_cli(Engine *e, int argc, char **argv, char **err) {
  char fname[MAXPATHLEN];
  size_t len = strnlen(rosiehome, MAXPATHLEN);
  char *last = stpncpy(fname, rosiehome, (MAXPATHLEN - len - 1));
  last = stpncpy(last, CLI_LUAC, MAXPATHLEN - len - 1 - strlen(CLI_LUAC));
  *last = '\0';

  LOGf("Entering rosie_exec_cli, computed cli filename is %s\n", fname);

  ACQUIRE_ENGINE_LOCK(e);
  lua_State *L = e->L;
  luaL_requiref(L, "readline", luaopen_readline, 0);

  get_registry(engine_key);
  lua_setglobal(L, "cli_engine");
  
  pushargs(L, argc, argv);

  int status = luaL_loadfile(L, fname);
  if (status != LUA_OK) {
    LOGf("Failed to load cli from %s\n", fname);
    *err = strndup(lua_tostring(L, -1), MAXPATHLEN);
    lua_settop(L, 0);
    RELEASE_ENGINE_LOCK(e);
    return status;
  }  
  status = docall(L, 0, 1);
  if (status != LUA_OK) {
    const char *err = lua_tostring(L, -1);
    lua_pop(L, 1);  /* remove message */
    const char *progname = NULL;
    if (argv[0] && argv[0][0]) progname = argv[0];
    fprintf(stderr, "%s: error (%d) executing CLI (please report this as a bug):\n%s\n", progname, status, err);
  } else {
    status = lua_tointeger(L, -1);
  }
  lua_settop(L, 0);
  RELEASE_ENGINE_LOCK(e);
  return status;
}

/* ----------------------------------------------------------------------------------------
 * Functions to support the Lua repl for debugging
 * ----------------------------------------------------------------------------------------
 */

#ifdef LUADEBUG

static int rosie_exec_lua_repl(Engine *e, int argc, char **argv) {
  LOG("Entering rosie_exec_lua_repl\n");

  ACQUIRE_ENGINE_LOCK(e);
  lua_State *L = e->L;
  luaL_requiref(L, "readline", luaopen_readline, 0);

  get_registry(engine_key);
  lua_setglobal(L, "cli_engine");
  
  pushargs(L, argc, argv);
  lua_repl(L, argv[0]);
  lua_settop(L, 0);
  RELEASE_ENGINE_LOCK(e);
  return SUCCESS;
}

#endif	/* LUADEBUG */


/* ----------------------------------------------------------------------------------------
 * Main (CLI)
 * ----------------------------------------------------------------------------------------
 */

static const char *progname = "rosie"; /* default */

int main (int argc, char **argv) {
  str messages;
  int invoke_repl = 0;

  if (argv[0] && argv[0][0]) progname = argv[0];

  Engine *e = rosie_new(&messages);
  if (!e) {
    fprintf(stderr, "Error: %.*s\n", messages.len, messages.ptr);
    exit(1);
  }

  if ((argc > 0) && argv[1] && !strncmp(argv[1], "-D", 3)) {
    invoke_repl = 1;
    for (int i = 1; i < argc-1; i++) argv[i] = argv[i+1];
    argv[argc-1] = (char *)'\0';
    argc = argc - 1;
  }

  char *err;
  int status = rosie_exec_cli(e, argc, argv, &err);

  if (invoke_repl) {
#ifdef LUADEBUG
    printf("Entering %s\n", LUA_COPYRIGHT);
    rosie_exec_lua_repl(e, argc, argv);
#else
    fprintf(stderr, "%s: no lua debug support available\n", progname);
#endif
  }

  rosie_finalize(e);
  return status;
}

