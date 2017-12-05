/*  -*- Mode: C; -*-                                                         */
/*                                                                           */
/*  dtest.c      Statically linking librosie.o                               */
/*                                                                           */
/*  © Copyright IBM Corporation 2017.                                        */
/*  LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)  */
/*  AUTHOR: Jamie A. Jennings                                                */

#include <string.h>
#include "../librosie.h"

//   gcc -I../../submodules/lua/include -DDEBUG=1 -o dtest.o -c dtest.c
//   gcc -o dtest dtest.o librosie.o liblua/*.o

/* Compile with DEBUG=1 to enable logging */
//#ifdef DEBUG
#define LOGGING 1
//#else
//#define LOGGING 0
//#endif

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

#define STR(literal) rosie_new_string((byte_ptr)(literal), strlen((literal)));



int main() {

  printf("*** Important note: This sample program will only work if it can find\n\
*** the rosie installation in the same directory as this executable,\n\
*** under the name 'rosie'.\n\
");

  str errors;

  printf("ABOUT TO CALL rosie_new\n"); fflush(NULL);

  void *engine = rosie_new(&errors);
  printf("AFTER CALL to rosie_new\n"); fflush(NULL);

  if (engine == NULL) {
    LOG("rosie_new failed\n");
    return FALSE;
  }
  LOG("obtained rosie matching engine\n");

  int err;
  int ok;
  str pkgname;
  pkgname = STR("all");
  errors = STR("");
  err = rosie_import(engine, &ok, &pkgname, NULL, &errors);
  printf("AFTER CALL to rosie_import\n"); fflush(NULL);

  if (err) {
    LOG("rosie call failed: import library \"all\"\n");
    goto quit;
  }
  if (!ok) {
    printf("failed to import the \"all\" library with error code %d\n", ok);
    goto quit;
  }

  int pat;
  str expression = STR("all.things");
  err = rosie_compile(engine, &expression, &pat, &errors);
  if (err) {
    LOG("rosie call failed: compile expression\n");
    goto quit;
  }
  if (!pat) {
    printf("failed to compile expression; error returned was:\n");
    if (errors.ptr != NULL) {
      printf("%s\n", errors.ptr);
    }
    else {
      printf("no error message given\n");
    }
    goto quit;
  }

  str input = STR("1234");
  match m;
  err = rosie_match(engine, pat, 1, "json", &input, &m);
  if (err) {
    LOG("rosie call failed: match");
    goto quit;
  }
  if (!m.data.ptr) {
    printf("match failed\n");
  }
  else {
    printf("match data is: %.*s\n", m.data.len, m.data.ptr);
  }

#define SYSLOG_RPL "/Users/jjennings/Dev/private/rosie_perf_test/syslog.rpl"
  printf("Loading %s... ", SYSLOG_RPL);
  str fn = STR(SYSLOG_RPL);
  err = rosie_loadfile(engine, &ok, &fn, &pkgname, &errors);
  if (err) {
       LOG("rosie call failed: loadfile");
       goto quit;
  }
  if (!ok) {
       printf("\nLoadfile failed\n");
  } else {
       printf("done.\n");
  }
  printf("Message returned: %s\n", errors.ptr);
	    

  expression = STR("syslog");
  err = rosie_compile(engine, &expression, &pat, &errors);
  if (err) {
    LOG("rosie call failed: compile expression\n");
    goto quit;
  }
  if (!pat) {
    printf("failed to compile expression; error returned was:\n");
    if (errors.ptr != NULL) {
      printf("%s\n", errors.ptr);
    }
    else {
      printf("no error message given\n");
    }
    goto quit;
  }

#define DATAFILE "/Users/jjennings/Data/syslog2M.log"
//  str datafn = STR(DATAFILE);
//  str empty = STR("");
  int cin, cout, cerr;
  err = rosie_matchfile(engine, pat, "json", 0, DATAFILE, "", "", &cin, &cout, &cerr, &errors);
  if (err) {
    LOG("rosie call failed: matchfile");
    goto quit;
  }



 quit:
  rosie_finalize(engine);
  
}
