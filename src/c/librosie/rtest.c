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
	  printf(" [%d] len=%d, ptr=%s\n", i, str->len, (str->ptr ? str->ptr : (uint8_t *)""));
     }
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

     initialize(QUOTE_EXPAND(ROSIE_HOME));	/* initialize Rosie */

     struct string *initial_config = &CONST_STRING("{\"name\":\"Episode IV: A New Engine\"}");
     struct stringArray retvals = new_engine(initial_config);
  
     print_results(retvals, "new_engine");
     /* LOGf("retvals.n is: %d\n", retvals.n); */
     /* LOGf("retvals[0].len is: %d\n", stringArrayRef(retvals,0)->len); */
     /* LOGf("retvals[0].ptr is: %s\n", (char *) stringArrayRef(retvals,0)->ptr); */

     struct string *code = stringArrayRef(retvals,0);
     LOGf("code->len is: %d\n", code->len);
     LOGf("code->ptr is: %s\n", (char *) code->ptr);

     char *true_value = "true";
     if (memcmp(code->ptr, true_value, (size_t) code->len)) {
	  struct string *err = stringArrayRef(retvals,1);
	  printf("Error in new_engine: %s\n", err ? (char *) err->ptr : "NO MESSAGE");
	  exit(-1);
     }

     struct string *eid_string = copy_string_ptr(stringArrayRef(retvals, 1));
     if (!eid_string) {
	  printf("eid_string is NULL\n");
	  exit(-1);
     }
     printf("eid_string: len=%d string=%s\n", eid_string->len, (char *)eid_string->ptr);

     free_stringArray(retvals);
  
     struct string *null = &(CONST_STRING("null"));

     struct stringArray r = rosie_api( "get_environment", eid_string, null);	   
     print_results(r, "get_environment");
     free_stringArray(r);

     struct string *arg = &(CONST_STRING("{\"expression\": \"[:digit:]+\", \"encode\": \"json\"}"));

     r = rosie_api( "configure_engine", eid_string, arg); 
     print_results(r, "configure_engine");
     free_stringArray(r);

     r = inspect_engine(eid_string); 
     print_results(r, "inspect_engine");
     free_stringArray(r);

     arg = &CONST_STRING("123");
     r = match(eid_string, arg); 
     print_results(r, "match");
     uint8_t *code2 = r.ptr[0]->ptr;
     uint8_t *match2 = r.ptr[1]->ptr;
     printf("code: %s\n", (char *)code2);
     printf("match: %s\n", (char *)match2);
     
     struct string js_str = {r.ptr[1]->len, r.ptr[1]->ptr};
     struct stringArray js_array = json_decode(&js_str);
     print_results(js_array, "json_decode");
     uint8_t *js_code2 = r.ptr[0]->ptr;
     uint8_t *js_match2 = r.ptr[1]->ptr;
     printf("json decode code: %s\n", (char *) js_code2);
     printf("json decode match: %s\n", (char *) js_match2);

     free_stringArray(r);
     free_stringArray(js_array);

     arg = &CONST_STRING("123 abcdef");
     r = match(eid_string, arg); 
     print_results(r, "match");
     free_stringArray(r);

     arg = &CONST_STRING("hi");
     r = match(eid_string, arg); 
     print_results(r, "match");
     free_stringArray(r);

     char *foo = "1239999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999";
     struct string *foo_string = &CONST_STRING(foo);

/* Guard against running a high iteration loop with verbose output */
#if DEBUG==0
     int M = 1000000;
#else
     int M = 1;
#endif
     printf("Looping..."); fflush(stdout);
     for (int i=0; i<5*M; i++) {
	  r = match(eid_string, foo_string);
	  code = stringArrayRef(r, 0);
	  if (memcmp(code->ptr, true_value, (size_t) code->len)) {
	       struct string *err = stringArrayRef(retvals,1);
	       printf("Error in match: %s\n", err ? (char *) err->ptr : "NO MESSAGE");
	  }
	  else {
	       LOGf("Match returned: %s\n", stringArrayRef(r,1)->ptr);
	       struct string js_str = {r.ptr[1]->len, r.ptr[1]->ptr};
	       struct stringArray js_array = json_decode(&js_str);
#if DEBUG==1
	       print_results(js_array, "json_decode");
#endif
	       free_stringArray(js_array);
	  }

	  free_stringArray(r);
     }
     printf(" done.\n");

     delete_engine(eid_string);
     free_string_ptr(eid_string);
     finalize();

     return EXIT_SUCCESS;

}

