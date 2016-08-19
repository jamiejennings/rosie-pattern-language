/*  -*- Mode: C/l; -*-                                                       */
/*                                                                           */
/*  librosie.h                                                               */
/*                                                                           */
/*  © Copyright IBM Corporation 2016.                                        */
/*  LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)  */
/*  AUTHOR: Jamie A. Jennings                                                */

#define TRUE 1
#define FALSE 0

typedef uint8_t * byte_ptr;

struct string {
     uint32_t len;
     byte_ptr ptr;
};

struct stringArray {
     uint32_t n;
     struct string **ptr;
};

#define CONST_STRING(str) (struct string) {strlen(str), (byte_ptr)str}
#define stringArrayRef(name, pos) (((name).n > (pos)) ? ((name).ptr[(pos)]) : '\0')

struct string *new_string(char *msg, size_t len);
struct stringArray *new_stringArray();
void free_string(struct string s);
void free_string_ptr(struct string *s);
void free_stringArray(struct stringArray r);
void free_stringArray_ptr(struct stringArray *r);

void *initialize(struct string *rosie_home, struct stringArray *msgs);
void finalize(void *L);

#include "librosie_gen.h"

