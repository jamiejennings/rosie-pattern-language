/*  -*- Mode: C/l; -*-                                                       */
/*                                                                           */
/*  registry.c   Part of librosie.c                                          */
/*                                                                           */
/*  © Copyright Jamie A. Jennings 2017.                                      */
/*  LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)  */
/*  AUTHOR: Jamie A. Jennings                                                */

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
  violation_strip_key,
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

