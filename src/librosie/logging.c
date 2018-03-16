/*  -*- Mode: C/l; -*-                                                       */
/*                                                                           */
/*  logging.c  Part of librosie.c                                            */
/*                                                                           */
/*  © Copyright Jamie A. Jennings 2017.                                      */
/*  LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)  */
/*  AUTHOR: Jamie A. Jennings                                                */


/* display() is used in only the most awkward situations, when there
   is no easy way to return a specific error to the caller, AND when
   we do not want to ask the user to recompile with LOGGING in order
   to understand that something very strange and unrecoverable occurred. 
*/
static void display (const char *msg) {
  fprintf(stderr, "librosie: %s\n", msg);
  fflush(NULL);
}

/* ----------------------------------------------------------------------------------------
 * Logging and debugging: Compile with DEBUG=1 to enable logging
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

#if 0
static void itemDump (lua_State *L, int pos) {
  int t = lua_type(L, pos);
  switch (t) {
  case LUA_TSTRING:  /* strings */
    fprintf(stderr, "'%s'", lua_tostring(L, pos));
    break;
  case LUA_TBOOLEAN:  /* booleans */
    fprintf(stderr, "%s", (lua_toboolean(L, pos) ? "true" : "false"));
    break;
  case LUA_TNUMBER:  /* numbers */
    fprintf(stderr, "%g", lua_tonumber(L, pos));
    break;
  default:  /* other values */
    fprintf(stderr, "%s", lua_typename(L, t));
    break;
  }
}

static void tableDump (lua_State *L, int pos) {
  lua_pushnil(L);
  pos -= 1;
  while (lua_next(L, pos) != 0) {
    itemDump(L, -2);		/* key */
    fprintf(stderr, " (%s) -> ", lua_typename(L, lua_type(L, -2)));
    itemDump(L, -1);		/* value */
    fprintf(stderr, " (%s); ", lua_typename(L, lua_type(L, -1)));
    /*  keep 'key' for next() */
    lua_pop(L, 1);
  }
  fprintf(stderr, "\n");
}
#endif

#ifdef DEBUG
static void check_type(const char *thing, int t, int expected) {
  if (t != expected)
    LOGf("type mismatch for %s.  received %d, expected %d.\n", thing, t, expected);
}
#define CHECK_TYPE(label, typ, expected_typ) \
  do { if (DEBUG) check_type((label), (typ), (expected_typ)); } while (0)
#else
#define CHECK_TYPE(label, typ, expected_typ)
#endif

