/*  -*- Mode: C/l; -*-                                                       */
/*                                                                           */
/* rosie.c      Create a Lua state, load Rosie, expose the Rosie API         */
/*                                                                           */
/*  © Copyright IBM Corporation 2016.                                        */
/*  LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)  */
/*  AUTHOR: Jamie A. Jennings                                                */


/* ROSIE_HOME defined on the command line during compilation (see Makefile)  */

#ifndef ROSIE_HOME
#error "ROSIE_HOME not defined.  Check CFLAGS in Makefile?"
#endif

#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>

#include "librosie.h"

void print_results(struct stringArray r, const char *name) {
     printf("Results from %s: n=%d\n", name, r.n);
     struct string **str_ptr_ptr = r.ptr;
     for (uint32_t i=0; i<r.n; i++) {
	  struct string *str = str_ptr_ptr[i];
	  printf(" [%d] len=%d, ptr=%s\n", i, str->len, (str->ptr ? str->ptr : (byte_ptr)""));
     }
}
     
struct string *copy_string_ptr(struct string *src) { 
     struct string *dest = malloc(sizeof(struct string)); 
     dest->len = src->len; 
     dest->ptr = malloc(sizeof(uint8_t)*src->len); 
     memcpy(dest->ptr, src->ptr, src->len); 
     return dest; 
} 

/*
---------------------------------------------------------------------------------------------------
 JSON encode/decode for testing
--------------------------------------------------------------------------------------------------- 
*/

#define EXIT_JSON_DECODE_ERROR -1
#define EXIT_JSON_ENCODE_ERROR -2

struct stringArray json_decode(lua_State *LL, struct string *js_string) {
     lua_getglobal(LL, "json");
     lua_getfield(LL, -1, "decode");
//     LOGf("Fetched json.decode, and top of stack is a %s\n", lua_typename(LL, lua_type(LL, -1)));
     lua_pushlstring(LL, (char *) js_string->ptr, js_string->len);
//     LOG("About to call json.decode\n");
//     LOGstack(LL);
     int status = lua_pcall(LL, 1, 1, 0);                   /* call 'json.decode(js_string)' */  
     if (status != LUA_OK) {  
	  printf(lua_pushfstring(LL, "Internal error: cannot json.decode %s (%s)", js_string->ptr, lua_tostring(LL, -1)));  
	  exit(EXIT_JSON_DECODE_ERROR);  
     }  
//     LOG("After call to json.decode\n");
//     LOGstack(LL);

     /* Since we can't return a lua table to C, we will encode it again and return that */
     lua_getfield(LL, -2, "encode");
//     LOGf("Fetched json.encode, and top of stack is a %s\n", lua_typename(LL, lua_type(LL, -1)));
     lua_insert(LL, -2);	/* move the table produced by decode to the top */
//     LOG("About to call json.encode\n");
//     LOGstack(LL);
     status = lua_pcall(LL, 1, 1, 0);                   /* call 'json.encode(table)' */  
     if (status != LUA_OK) {  
	  printf(lua_pushfstring(LL, "Internal error: json.encode failed (%s)", js_string->ptr, lua_tostring(LL, -1)));  
	  exit(EXIT_JSON_ENCODE_ERROR);  
     }  
//     LOG("After call to json.encode\n");
//     LOGstack(LL);

     uint32_t nretvals = 2;
     struct string **list = malloc(sizeof(struct string *) * nretvals);
     size_t len;
     char *str;
     if (TRUE) {len=4; str="true";}
     else {len=5; str="false";}
//     LOGf("len=%d, str=%s", (int) len, (char *)str);
     list[0] = malloc(sizeof(struct string));
     list[0]->len = len;
     list[0]->ptr = malloc(sizeof(uint8_t)*(len+1));
     memcpy(list[0]->ptr, str, len);
     list[0]->ptr[len] = 0; /* so we can use printf for debugging */	  
//     LOGf("  Encoded as struct string: len=%d ptr=%s\n", (int) list[0]->len, list[0]->ptr);

     str = (char *) lua_tolstring(LL, -1, &len);
     list[1] = malloc(sizeof(struct string));
     list[1]->len = len;
     list[1]->ptr = malloc(sizeof(uint8_t)*(len+1));
     memcpy(list[1]->ptr, str, len);
     list[1]->ptr[len] = 0; /* so we can use printf for debugging */	  
//     LOGf("  Encoded as struct string: len=%d ptr=%s\n", (int) list[1]->len, list[1]->ptr);

     lua_pop(LL, 2);    /* discard the result string and the json table */  
     return (struct stringArray) {2, list};

}  

/*
---------------------------------------------------------------------------------------------------
 main 
--------------------------------------------------------------------------------------------------- 
*/

#define QUOTE_EXPAND(name) QUOTE(name)		    /* expand name */
#define QUOTE(thing) #thing			    /* stringify it */

int main () {

     printf("\nTo suppress logging messages, build this test with: make macosx COPT=\"-DDEBUG=0\"\n\n");

     struct stringArray retvals;
     void *engine = initialize(QUOTE_EXPAND(ROSIE_HOME), &retvals);

     if (!engine) {
	  printf("Initialization error!   Details:\n");
	  print_results(retvals, "initialize");
	  exit(-1);
     }

     print_results(retvals, "initialize"); 
     
     /* struct string *initial_config = &CONST_STRING("{\"name\":\"Episode IV: A New Engine\"}"); */
     /* retvals = new_engine(engine, initial_config); */
     /* print_results(retvals, "new_engine"); */

     struct string *code = stringArrayRef(retvals,0);
     LOGf("code->len is: %d\n", code->len);
     LOGf("code->ptr is: %s\n", (char *) code->ptr);

     char *true_value = "true";
     if (memcmp(code->ptr, true_value, (size_t) code->len)) {
	  struct string *err = stringArrayRef(retvals,1);
	  printf("Error in new_engine: %s\n", err ? (char *) err->ptr : "NO MESSAGE");
	  exit(-1);
     }

     free_stringArray(retvals);

     struct string *null = &(CONST_STRING("null"));

     struct stringArray r = rosie_api(engine, "get_environment", null);	   
     print_results(r, "get_environment");
     free_stringArray(r);

     struct string *arg = &(CONST_STRING("{\"expression\": \"[:digit:]+\", \"encode\": \"json\"}"));

     r = rosie_api(engine, "configure_engine", arg); 
     print_results(r, "configure_engine");
     free_stringArray(r);

     r = inspect_engine(engine); 
     print_results(r, "inspect_engine");
     free_stringArray(r);

     arg = &CONST_STRING("123");
     r = match(engine, arg); 
     print_results(r, "match");
     byte_ptr code2 = r.ptr[0]->ptr;
     byte_ptr match2 = r.ptr[1]->ptr;
     printf("code: %s\n", (char *)code2);
     printf("match: %s\n", (char *)match2);
     
     struct string js_str = {r.ptr[1]->len, r.ptr[1]->ptr};
     struct stringArray js_array = json_decode(engine, &js_str);
     print_results(js_array, "json_decode");
     byte_ptr js_code2 = r.ptr[0]->ptr;
     byte_ptr js_match2 = r.ptr[1]->ptr;
     printf("json decode code: %s\n", (char *) js_code2);
     printf("json decode match: %s\n", (char *) js_match2);
     free_stringArray(js_array);

     free_stringArray(r);

     arg = &CONST_STRING("123 abcdef");
     r = match(engine, arg); 
     print_results(r, "match");
     free_stringArray(r);

     arg = &CONST_STRING("hi");
     r = match(engine, arg); 
     print_results(r, "match");
     free_stringArray(r);

     char *foo2 = "1230000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";
     struct string *foo_string2 = &CONST_STRING(foo2);

     r = match(engine, foo_string2); 
     print_results(r, "match");

/* Guard against running a high iteration loop with verbose output */
     int M = 1000000;
     M = 1;
#if DEBUG==0
     M = 1;
#endif

     int for_real = TRUE;

     char *foo = "1239999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999";
     struct string *foo_string = &CONST_STRING(foo);

     printf("Looping..."); fflush(stdout);
     for (int i=0; i<5*M; i++) {
	  if (for_real) {
	       free_stringArray(r);
	       r = match(engine, foo_string);
	  }
	  code = stringArrayRef(r, 0);
	  if (memcmp(code->ptr, true_value, (size_t) code->len)) {
	       struct string *err = stringArrayRef(r,1);
	       printf("Error in match: %s\n", err ? (char *) err->ptr : "NO MESSAGE");
	  }
	  else {
	       LOGf("Match returned: %s\n", stringArrayRef(r,1)->ptr);
	       struct string js_str = {r.ptr[1]->len, r.ptr[1]->ptr};
	       struct stringArray js_array = json_decode(engine, &js_str);
#if DEBUG==1
	       print_results(js_array, "json_decode");
#endif
	       free_stringArray(js_array);
	  }
     }
     free_stringArray(r);
     printf(" done.\n");

     finalize(engine);

     return EXIT_SUCCESS;

}

