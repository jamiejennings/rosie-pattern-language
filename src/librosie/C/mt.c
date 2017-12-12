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
#include "../librosie.h"

/* Compile with DEBUG=1 to enable logging */
#ifdef DEBUG
#define LOGGING 1
#else
#define LOGGING 0
#endif

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

#define E_BAD_ARG -1
#define E_ENGINE_CREATE -3
#define E_ENGINE_IMPORT -4

void *make_engine() {
  int ok;
  str errors;
  str pkgname = STR("all");
  void *engine = rosie_new(&errors);
  rosie_free_string(pkgname);
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
  int err = rosie_import(engine, &ok, &pkgname, NULL, &errors);
  if (err) {
    printf("Call to rosie_import failed.\n");
    if (errors.ptr) printf("%s", errors.ptr);
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

  LOGf("Engine %p created\n", engine);
  return engine;
}  

#define INFILE "../../../test/system.log"

int compile(void *engine, str expression) {
  int pat;
  str errors = STR("");		/* WTF??? */
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


int r=0;			/* TEMPORARILY global */

void *do_work(void *engine) {
  printf("Thread running with engine %p\n", engine); fflush(NULL);
  int cin, cout, cerr;
  int pat;
  str exp = STR("all.things");

  pat = compile(engine, exp);
  rosie_free_string(exp);

  char outfile[20];
  sprintf(&outfile[0], "%p.out", engine);
  str *errors = NULL;
  for (int i=0; i<r; i++) {
    printf("Engine %p iteration %d\n", engine, i);
    int err = rosie_matchfile(engine,
			      pat,
			      "json",
			      0,	/* not whole file at once */
			      INFILE, outfile, "",
			      &cin, &cout, &cerr,
			      errors);
    if (err) printf("*** Error calling matchfile\n");
    if (errors && errors->ptr) {
      printf("matchfile() returned: %s\n", errors->ptr);
      rosie_free_string_ptr(errors);
    }
    printf("Engine %p matchfile() returned: %d, %d, %d\n", engine, cin, cout, cerr);
  }
  pthread_exit(do_work);		/* any non-null pointer */
}

/* Main */

int main(int argc, char **argv) {

  if (argc != 3) {
    printf("Usage: %s <number of threads> <number of repetitions>\n", argv[0]);
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

  void **engine = calloc(n, sizeof(void *));
  pthread_t *thread = calloc(n, sizeof(pthread_t));

  printf("Making engines for %d threads\n", n);
  for (int i=0; i<n; i++) engine[i] = make_engine();

  printf("Creating %d threads\n", n);
  for (int i=0; i<n; i++) {
    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_attr_setstacksize(&attr, (size_t) 1024*1024*10); /* !@# WHAT VALUE TO USE? */
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
