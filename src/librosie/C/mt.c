/*  -*- Mode: C; -*-                                                         */
/*                                                                           */
/*  mt.c   Statically linked multi-thread librosie client                    */
/*                                                                           */
/*  © Copyright IBM Corporation 2017.                                        */
/*  LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)  */
/*  AUTHOR: Jamie A. Jennings                                                */

#include <string.h>
#include <stdlib.h>
#include <pthread.h>
#include "librosie.h"

/* 
 * Stack size in bytes, established as a pthread attribute:
 *
 * 784kb works in this sample program (on OS X 10.13.2,
 * clang-900.0.39.2).  The right value to use will depend on what else
 * the thread will be doing.
 */
#define ROSIE_STACK_SIZE ((size_t) 1024*1024*1)

#define STR(literal) rosie_new_string((byte_ptr)(literal), strlen((literal)));

#define E_BAD_ARG -1
#define E_ENGINE_CREATE -3
#define E_ENGINE_IMPORT -4

void *make_engine() {
  int ok;
  str errors;
  str pkgname = STR("all");
  str actual_pkgname;
  void *engine = rosie_new(&errors);
  if (!engine) {
    printf("Call to rosie_new failed.\n");
    if (errors.ptr) printf("%s", errors.ptr);
    if (engine == NULL) {
      printf("Creation of engine failed.\n");
      printf("Important note: This sample program will only work if it can find\n\
the rosie installation in the same directory as this executable,\n	\
under the name 'rosie'.\n\
");
    exit(E_ENGINE_CREATE);
    }
  }
  int err = rosie_import(engine, &ok, &pkgname, NULL, &actual_pkgname, &errors);
  rosie_free_string(pkgname);
  if (actual_pkgname.ptr != NULL) rosie_free_string(actual_pkgname);

  if (err) {
    printf("Call to rosie_import failed.\n");
    if (errors.ptr) {
	 printf("%s", errors.ptr);
	 rosie_free_string(errors);
    }
    exit(E_ENGINE_IMPORT);
  }
  if (!ok) {
    printf("Import failed for engine %p\n", engine);
    if (errors.ptr) {
      printf("%s\n", errors.ptr);
      rosie_free_string(errors);
    }
    exit(E_ENGINE_IMPORT);
  }

  if (errors.ptr) {
    rosie_free_string(errors);
  }
  printf("Engine %p created\n", engine);
  return engine;
}  

int compile(void *engine, str expression) {
  int pat;
  str errors;
  int err = rosie_compile(engine, &expression, &pat, &errors);
  if (err) {
    printf("rosie call failed: compile expression\n");
    return ERR_ENGINE_CALL_FAILED;
  }
  if (!pat) {
    printf("failed to compile expression; error returned was:\n");
    if (errors.ptr) {
      printf("%s\n", errors.ptr);
      rosie_free_string(errors);
    }
    else {
      printf("no error message given\n");
    }
    return ERR_ENGINE_CALL_FAILED;
  }
  if (errors.ptr) {
    rosie_free_string(errors);
  }
  return pat;
}


/* Globals because we can. */
int r=0;
char *infile;

void *do_work(void *engine) {
  printf("Thread running with engine %p\n", engine); fflush(NULL);
  int cin, cout, cerr;
  int pat;
  str exp = STR("all.things");
  str errors;

  pat = compile(engine, exp);
  rosie_free_string(exp);

  char outfile[40];
  sprintf(&outfile[0], "/tmp/%p.out", engine);
  for (int i=0; i<r; i++) {
    printf("Engine %p iteration %d writing file %s\n", engine, i, outfile);
    int err = rosie_matchfile(engine,
			      pat,
			      "json",
			      0,	/* not whole file at once */
			      infile, outfile, "",
			      &cin, &cout, &cerr,
			      &errors);
    if (err) printf("*** Error calling matchfile\n");
    if (errors.ptr) {
      printf("matchfile() returned: %.*s\n", errors.len, errors.ptr);
      rosie_free_string(errors);
    }
    printf("Engine %p matchfile() returned: %d, %d, %d\n", engine, cin, cout, cerr);
  }
  pthread_exit(do_work);		/* any non-null pointer */
}

/* Main */

int main(int argc, char **argv) {

  if (argc != 4) {
    printf("Usage: %s <number of threads> <number of repetitions> <text file to process>\n", argv[0]);
    exit(E_BAD_ARG);
  }

  int n = atoi(argv[1]);
  if (n < 1) {
    printf("Argument (number of threads) is < 1 or not a number: %s\n", argv[1]);
    exit(E_BAD_ARG);
  }

  r = atoi(argv[2]);
  if (r < 1) {
    printf("Argument (number of repetitions) is < 1 or not a number: %s\n", argv[2]);
    exit(E_BAD_ARG);
  }

  infile = (char *)argv[3];
  if (infile == NULL) {
    printf("Argument (text file to process) is empty\n");
    exit(E_BAD_ARG);
  }

  printf("Input file is %s\n", infile);

  void **engine = calloc(n, sizeof(void *));
  pthread_t *thread = calloc(n, sizeof(pthread_t));

  printf("Making engines for %d threads\n", n);
  for (int i=0; i<n; i++) engine[i] = make_engine();

  printf("Creating %d threads\n", n);
  for (int i=0; i<n; i++) {
    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_attr_setstacksize(&attr, ROSIE_STACK_SIZE);
    int err = pthread_create(&thread[i], &attr, do_work, engine[i]);
    printf("thread[%d] = %p\n", i, &thread[i]); fflush(NULL);
    if (err) {
      printf("Error in pthread_create(), thread #%d\n", i);
      fflush(NULL);
      thread[i] = NULL;
    }
  }
  
  printf("Joining with %d threads\n", n);
  for (int i=0; i<n; i++) {
    void *status;
    if (thread[i]) {
      printf("Waiting on thread %d (%p)\n", i, &thread[i]); fflush(NULL);
      pthread_join(thread[i], &status);
      if (status != &do_work) {
	printf("*** Wrong status returned from thread %d (%p)\n", i, &thread[i]);
	fflush(NULL);
      }
    }
  }
    
  printf("Finalizing engines\n");
  for (int i=0; i<n; i++) rosie_finalize(engine[i]);
  printf("Freeing thread-related data\n");
  free(engine);
  free(thread);

  printf("Exiting\n"); fflush(NULL);
  exit(0);
  
}
