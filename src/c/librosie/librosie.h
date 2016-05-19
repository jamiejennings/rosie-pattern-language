/*  -*- Mode: C/l; -*-                                                       */
/*                                                                           */
/*  librosie.h                                                               */
/*                                                                           */
/*  © Copyright IBM Corporation 2016.                                        */
/*  LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)  */
/*  AUTHOR: Jamie A. Jennings                                                */


extern int bootstrap (lua_State *L, const char *rosie_home);
extern void require (lua_State *L, const char *name, int assign_name);
extern void initialize(lua_State *L, const char *rosie_home);
extern int rosie_api(lua_State *L, const char *name, ...);

/* !@# */
extern void l_message (const char *pname, const char *msg);
