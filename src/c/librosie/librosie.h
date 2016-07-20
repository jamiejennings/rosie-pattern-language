/*  -*- Mode: C/l; -*-                                                       */
/*                                                                           */
/*  librosie.h                                                               */
/*                                                                           */
/*  © Copyright IBM Corporation 2016.                                        */
/*  LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)  */
/*  AUTHOR: Jamie A. Jennings                                                */

#define TRUE 1
#define FALSE 0

struct string {
     uint32_t len;
     uint8_t *ptr;
};

struct string_array {
     uint32_t n;
     struct string **ptr;
};

struct string_array2 {
     uint32_t n;
     struct string *ptr;
};

void free_string(struct string foo);
uint32_t testbyvalue(struct string foo);
uint32_t testbyref(struct string *foo);
struct string testretstring(struct string *foo);
struct string_array testretarray(struct string foo);
struct string_array2 testretarray2(struct string foo);

#define CONST_STRING(str) (struct string) {strlen(str), (uint8_t *)str}
#define FREE_STRING(s) { free((s).ptr); (s).ptr=0; (s).len=0; }


/* extern int bootstrap (lua_State *L, const char *rosie_home); */
void require (const char *name, int assign_name);
void initialize(const char *rosie_home);
struct string rosie_api(const char *name, ...);
struct string new_engine(struct string *config);

/* !@# */
extern void l_message (const char *pname, const char *msg);
extern lua_State *get_L();


