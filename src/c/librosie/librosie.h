/*  -*- Mode: C/l; -*-                                                       */
/*                                                                           */
/*  librosie.h                                                               */
/*                                                                           */
/*  © Copyright IBM Corporation 2016.                                        */
/*  LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)  */
/*  AUTHOR: Jamie A. Jennings                                                */

#define MAXTHREADS 100
#define MAXPATHSIZE 4096

/* ------------------------------------------------------------------------- */

#define TRUE 1
#define FALSE 0

#include "lauxlib.h"
#include "lualib.h"

typedef uint8_t * byte_ptr;

struct string {
     uint32_t len;
     byte_ptr ptr;
};

struct stringArray {
     uint32_t n;
     struct string **ptr;
};

struct string *new_string(char *msg, size_t len);
struct stringArray *new_stringArray();
void free_string(struct string s);
void free_string_ptr(struct string *s);
void free_stringArray(struct stringArray r);
void free_stringArray_ptr(struct stringArray *r);

#define CONST_STRING(str) (struct string) {strlen(str), (byte_ptr)str}
#define stringArrayRef(name, pos) (((name).n > (pos)) ? ((name).ptr[(pos)]) : '\0')

void *initialize(const char *rosie_home, struct stringArray *msgs);
void finalize(void *L);

#include "librosie_gen.h"



#ifdef DEBUG
#define LOGGING 1
#else
#define LOGGING 0
#endif

#define LOG(msg) \
     do { if (LOGGING) fprintf(stderr, "%s:%d:%s(): %s", __FILE__, \
			     __LINE__, __func__, msg); } while (0)

#define LOGf(fmt, ...) \
     do { if (LOGGING) fprintf(stderr, "%s:%d:%s(): " fmt, __FILE__, \
			     __LINE__, __func__, __VA_ARGS__); } while (0)

#define LOGstack(L) \
     do { if (LOGGING) stackDump(L); } while (0)

#define LOGprintArray(sa, caller_name) \
     do { if (LOGGING) print_stringArray(sa, caller_name); } while (0)
