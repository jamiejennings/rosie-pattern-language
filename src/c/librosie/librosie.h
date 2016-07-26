/*  -*- Mode: C/l; -*-                                                       */
/*                                                                           */
/*  librosie.h                                                               */
/*                                                                           */
/*  © Copyright IBM Corporation 2016.                                        */
/*  LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)  */
/*  AUTHOR: Jamie A. Jennings                                                */

#define TRUE 1
#define FALSE 0

#include "lauxlib.h"
#include "lualib.h"

struct string {
     uint32_t len;
     uint8_t *ptr;
};

struct stringArray {
     uint32_t n;
     struct string **ptr;
};

void free_string(struct string foo);
uint32_t testbyvalue(struct string foo);
uint32_t testbyref(struct string *foo);
struct string testretstring(struct string *foo);
struct stringArray testretarray(struct string foo);

#define CONST_STRING(str) (struct string) {strlen(str), (uint8_t *)str}
#define FREE_STRING(s) { free((s).ptr); (s).ptr=0; (s).len=0; }

#define stringArrayRef(name, pos) (((name).n > (pos)) ? ((name).ptr[(pos)]) : '\0')

/* extern int bootstrap (lua_State *L, const char *rosie_home); */
void require (const char *name, int assign_name);
void initialize(const char *rosie_home);
struct string *rosie_api(const char *name, ...);
struct stringArray new_engine(struct string *config);

#ifndef DEBUG
#define DEBUG 0
#endif

#define LOG(msg) \
     do { if (DEBUG) fprintf(stderr, "%s:%d:%s(): %s", __FILE__, \
			     __LINE__, __func__, msg); } while (0)

#define LOGf(fmt, ...) \
     do { if (DEBUG) fprintf(stderr, "%s:%d:%s(): " fmt, __FILE__, \
			     __LINE__, __func__, __VA_ARGS__); } while (0)

#define LOGstack(L) \
     do { if (DEBUG) stackDump(L); } while (0)

