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
	  printf(" [%d] len=%d, ptr=%s\n", i, str->len, str->ptr);
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
  
     LOGf("retvals.n is: %d\n", retvals.n);
     LOGf("retvals[0].len is: %d\n", stringArrayRef(retvals,0)->len);
     LOGf("retvals[0].ptr is: %s\n", (char *) stringArrayRef(retvals,0)->ptr);

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
     else printf("eid_string is ok\n");
     printf("eid_string: len=%d string=%s\n", eid_string->len, (char *)eid_string->ptr);

     free_stringArray(retvals);
  
     struct string *null = &(CONST_STRING("null"));

     struct stringArray r = rosie_api( "get_environment", eid_string, null);	   
     print_results(r, "get_environment");
     free_stringArray(r);

     struct string *arg = &(CONST_STRING("{\"expression\": \"[:digit:]+\", \"encode\": false}"));

     r = rosie_api( "configure_engine", eid_string, arg); 
     print_results(r, "configure_engine");
     free_stringArray(r);

     r = rosie_api( "inspect_engine", eid_string, null); 
     print_results(r, "inspect_engine");
     free_stringArray(r);

     arg = &CONST_STRING("123");
     r = rosie_api( "match", eid_string, arg); 
     print_results(r, "match");
     free_stringArray(r);

     arg = &CONST_STRING("123 abcdef");
     r = rosie_api( "match", eid_string, arg); 
     print_results(r, "match");
     free_stringArray(r);

     arg = &CONST_STRING("hi");
     r = rosie_api( "match", eid_string, arg); 
     print_results(r, "match");
     free_stringArray(r);

     delete_engine(eid_string);
     free_string_ptr(eid_string);
     finalize();

     return EXIT_SUCCESS;

}

