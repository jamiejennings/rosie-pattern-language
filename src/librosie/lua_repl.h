/*  -*- Mode: C/l; -*-                                                       */
/*                                                                           */
/*  lua_repl.h                                                               */
/*                                                                           */
/*  © Copyright Jamie A. Jennings 2018.                                      */
/*  LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)  */
/*  AUTHOR: Jamie A. Jennings                                                */

#ifndef lua_repl_h
#define lua_repl_h

#include <stdarg.h>
#include <stddef.h>


int lua_repl(lua_State *L, char *main_progname);

#define LUA_MULTRET	(-1)

/* thread status */
#define LUA_OK		0
#define LUA_YIELD	1
#define LUA_ERRRUN	2
#define LUA_ERRSYNTAX	3
#define LUA_ERRMEM	4
#define LUA_ERRGCMM	5
#define LUA_ERRERR	6

typedef struct lua_State lua_State;

#endif	/* lua_repl_h */
