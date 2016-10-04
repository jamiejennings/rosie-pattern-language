/*  -*- Mode: C/l; -*-                                                       */
/*                                                                           */
/* rtest.c      Example of using librosie from C                             */
/*                                                                           */
/*  © Copyright IBM Corporation 2016.                                        */
/*  LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)  */
/*  AUTHOR: Jamie A. Jennings                                                */

#include <stdlib.h> 
#include <stdio.h>
#include <string.h> 

#include "librosie.h"

/*
---------------------------------------------------------------------------------------------------
 utilities
--------------------------------------------------------------------------------------------------- 
*/

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


char *true_value = "true";
char *false_value = "false";

int ok(struct stringArray r) {
     struct string *code = stringArrayRef(r, 0);
     return !(memcmp(code->ptr, true_value, (size_t) code->len));
}

int matched(struct stringArray r) {
     struct string *code = stringArrayRef(r, 1);
     return (memcmp(code->ptr, false_value, (size_t) code->len));
}
	  
void report_on_match(struct stringArray r) {
     if (ok(r)) {
	  if (matched(r)) {
	       printf("Match!  Structure returned is: %s\n", stringArrayRef(r,1)->ptr);
	       printf("        Number of characters leftover in input: %s\n", stringArrayRef(r,2)->ptr);
	  }
	  else
	       printf("No match.\n");
     }
     else {
	  struct string *err = stringArrayRef(r,1);
	  printf("Error in call to match: %s\n", err ? (char *) err->ptr : "NO MESSAGE");
     }
}
     
void print_results(struct stringArray r, const char *name) {
     printf("Results from %s: n=%d\n", name, r.n);
     struct string **str_ptr_ptr = r.ptr;
     for (uint32_t i=0; i<r.n; i++) {
	  struct string *str = str_ptr_ptr[i];
	  printf(" [%d] len=%d, ptr=%s\n", i, str->len, (str->ptr ? str->ptr : (byte_ptr)""));
     }
}

/*
---------------------------------------------------------------------------------------------------
 main 
--------------------------------------------------------------------------------------------------- 
*/

int main () {

     if (LOGGING)
	  printf("\nTo suppress logging messages, build librosie.so WITHOUT this: DEBUG=1\n\n");
     else
	  printf("\nTo enable lots of logging messages, build librosie.so with: make DEBUG=1\n\n");

     printf("ROSIE_HOME is set to: %s\n", ROSIE_HOME);

     struct stringArray retvals;
     void *engine = initialize(&(CONST_STRING(ROSIE_HOME)), &retvals);
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
     printf("code->len is: %d\n", code->len);
     printf("code->ptr is: %s\n", (char *) code->ptr);

     if (!ok(retvals)) {
	  struct string *err = stringArrayRef(retvals,1);
	  printf("Error during initialization: %s\n", err ? (char *) err->ptr : "NO MESSAGE");
	  exit(-1);
     }

     free_stringArray(retvals);

     struct stringArray r = get_environment(engine, NULL);
     print_results(r, "get_environment");
     free_stringArray(r);

     struct string *arg = &(CONST_STRING("{\"expression\": \"[:digit:]+\", \"encode\": \"json\"}"));

     r = configure_engine(engine, arg); 
     print_results(r, "configure_engine");
     free_stringArray(r);

     r = inspect_engine(engine); 
     print_results(r, "inspect_engine");
     free_stringArray(r);

     arg = &CONST_STRING("123");
     printf("\nCalling match on input string: \"%s\"\n", arg->ptr);
     r = match(engine, arg, NULL); 
     print_results(r, "match");
     byte_ptr r_code = r.ptr[0]->ptr;
     byte_ptr r_match = r.ptr[1]->ptr;
     byte_ptr r_leftover = r.ptr[2]->ptr;
     printf("code: %s\n", (char *)r_code);
     printf("match: %s\n", (char *)r_match);
     printf("leftover: %s\n", (char *)r_leftover);
     free_stringArray(r);

     arg = &CONST_STRING("123 abcdef");
     printf("\nCalling match on input string: \"%s\"\n", arg->ptr);
     r = match(engine, arg, NULL); 
     print_results(r, "match");
     free_stringArray(r);

     arg = &CONST_STRING("hi");
     printf("\nCalling match on input string: \"%s\"\n", arg->ptr);
     r = match(engine, arg, NULL); 
     print_results(r, "match");
     free_stringArray(r);

     arg = &CONST_STRING("123xyz");
     printf("\nCalling match on input string: \"%s\"\n", arg->ptr);
     r = match(engine, arg, NULL); 
     report_on_match(r);
     free_stringArray(r);

     arg = &CONST_STRING("123999999999999999999999");
     printf("\nCalling match on input string: \"%s\"\n", arg->ptr);
     r = match(engine, arg, NULL);
     report_on_match(r);
     free_stringArray(r);

     finalize(engine);

     return 0;

}

