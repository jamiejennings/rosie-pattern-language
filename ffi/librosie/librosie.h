/*  -*- Mode: C/l; -*-                                                       */
/*                                                                           */
/*  librosie.h                                                               */
/*                                                                           */
/*  © Copyright IBM Corporation 2016, 2017.                                  */
/*  LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)  */
/*  AUTHOR: Jamie A. Jennings                                                */

#define TRUE 1
#define FALSE 0

#define MAX_PATH_LEN 4096

#include <stdint.h>

typedef uint8_t * byte_ptr;

struct rosieL_string {
     uint32_t len;
     byte_ptr ptr;
};

struct rosieL_stringArray {
     uint32_t n;
     struct rosieL_string **ptr;
};

#define CONST_STRING(str) (struct rosieL_string) {strlen(str), (byte_ptr)str} /* NOTE: Allocates on the stack! */
#define stringArrayRef(name, pos) (((name).n > (pos)) ? ((name).ptr[(pos)]) : '\0')

struct rosieL_string *rosieL_new_string(byte_ptr msg, size_t len);
struct rosieL_stringArray *rosieL_new_stringArray();
void rosieL_free_string(struct rosieL_string s);
void rosieL_free_string_ptr(struct rosieL_string *s);
void rosieL_free_stringArray(struct rosieL_stringArray r);
void rosieL_free_stringArray_ptr(struct rosieL_stringArray *r);

/* void *rosieL_initialize(struct rosieL_string *rosie_home, struct rosieL_stringArray *msgs); */
/* void rosieL_finalize(void *L); */

void *rosieL_initialize(struct rosieL_string *rosie_home, struct rosieL_stringArray *msgs);

/* #include "librosie_gen.h" */

