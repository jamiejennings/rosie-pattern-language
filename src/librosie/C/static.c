/*  -*- Mode: C; -*-                                                         */
/*                                                                           */
/*  dtest.c      Statically linking librosie.o                               */
/*                                                                           */
/*  © Copyright IBM Corporation 2017.                                        */
/*  LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)  */
/*  AUTHOR: Jamie A. Jennings                                                */

#include <string.h>
#include "../librosie.h"

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
     int exitStatus = 0;

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
    exitStatus = -1;
    return exitStatus;
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
    exitStatus = -2;
    goto quit;
  }
  if (!ok) {
    printf("failed to import the \"all\" library with error code %d\n", ok);
    exitStatus = -3;
    goto quit;
  }

  int pat;
  str expression = STR("all.things");
  err = rosie_compile(engine, &expression, &pat, &errors);
  if (err) {
    LOG("rosie call failed: compile expression\n");
    exitStatus = -4;
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
    exitStatus = -5;
    goto quit;
  }

  str input = STR("1234");
  match m;
  err = rosie_match(engine, pat, 1, "json", &input, &m);
  if (err) {
    LOG("rosie call failed: match");
    exitStatus = -6;
    goto quit;
  }
  if (!m.data.ptr) {
    printf("match failed\n");
    exitStatus = -7;
    goto quit;
  }
  else {
    printf("match data is: %.*s\n", m.data.len, m.data.ptr);
  }



 quit:
  rosie_finalize(engine);
  return exitStatus;
}
