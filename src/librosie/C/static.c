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
#define FREE(str) do { if ((str).ptr) rosie_free_string((str)); } while (0)



int main() {
     int exitStatus = 0;

  printf("*** Important note: This sample program will only work if it can find\n\
*** the rosie installation in the same directory as this executable,\n\
*** under the name 'rosie'.\n\
");

  str errors;

  printf("Calling rosie_new\n"); fflush(NULL);

  void *engine = rosie_new(&errors);

  if (engine == NULL) {
    LOG("rosie_new failed\n");
    exitStatus = -1;
    return exitStatus;
  }
  LOG("obtained rosie matching engine\n");

  int err;
  int ok;
  str pkgname, actual_pkgname;
  pkgname = STR("all");

  printf("Calling rosie_import\n"); fflush(NULL);
  err = rosie_import(engine, &ok, &pkgname, NULL, &actual_pkgname, &errors);
  FREE(pkgname);
  printf("Imported library named %s\n", actual_pkgname.ptr);
  FREE(actual_pkgname);
  
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
  FREE(errors);
  
  int pat;
  str expression = STR("all.things");
  err = rosie_compile(engine, &expression, &pat, &errors);
  FREE(expression);
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
  FREE(errors);

  str input = STR("1234");
  match m;
  err = rosie_match(engine, pat, 1, "json", &input, &m);
  FREE(input);
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
  
  str rplfile = STR("test.rpl");
  err = rosie_loadfile(engine, &ok, &rplfile, &actual_pkgname, &errors);
  FREE(rplfile);
  if (err) {
    LOG("rosie call failed: loadfile");
    exitStatus = -8;
    goto quit;
  }
  if (!ok) {
    printf("loadfile failed\n");
    exitStatus = -9;
    goto quit;
  }
  else {
       char *msg = ((actual_pkgname.ptr != NULL) ? (char *) actual_pkgname.ptr : "<no package>");
       printf("rpl file loaded successfully, package name is: %s\n", msg);
  }
  FREE(actual_pkgname);
  FREE(errors);

 quit:
  rosie_finalize(engine);
  return exitStatus;
}
