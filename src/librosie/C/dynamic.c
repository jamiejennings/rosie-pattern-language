/*  -*- Mode: C; -*-                                                         */
/*                                                                           */
/*  dynamic.c   Example client of librosie.dylib                             */
/*                                                                           */
/*  © Copyright IBM Corporation 2017.                                        */
/*  LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)  */
/*  AUTHOR: Jamie A. Jennings                                                */

/* To run:
   DYLD_LIBRARY_PATH=.. ./dynamic 
*/

#include <dlfcn.h>
#include <string.h>
#include <stdlib.h>
#include <libgen.h>		/* for basename, dirname (used for testing) */
#include "dynamic.h"

void *librosie;


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

#define displayf(fmt, ...) \
     do { fprintf(stderr, "%s:%d:%s(): " fmt, __FILE__, \
			       __LINE__, __func__, __VA_ARGS__);     \
	  fflush(NULL);						     \
     } while (0)


#define STR(literal) (*fp_rosie_new_string)((byte_ptr)(literal), strlen((literal)));

static char *get_libdir(void *symbol) {
  Dl_info dl;
  char *base, *dir;
  int ok = dladdr(symbol, &dl);
  if (!ok) {
    LOG("call to dladdr failed");
    return NULL;
  }
  LOGf("dli_fname is %s\n", dl.dli_fname);
  base = basename((char *)dl.dli_fname);
  dir = dirname((char *)dl.dli_fname);
  if (!base || !dir) {
    LOG("librosie: call to basename/dirname failed");
    return NULL;
  }
  char *libdir = strndup(dir, MAXPATHLEN);
  LOGf("libdir is %s, and libname is %s\n", libdir, base);
  return libdir;
}


/* Note: RTLD_GLOBAL is not default on Ubuntu.  Must be explicit.*/
static int init(const char *librosie_path){

  librosie = dlopen(librosie_path, RTLD_LAZY | RTLD_GLOBAL);
  if (librosie == NULL) {
    displayf("failed to dlopen %s\n", librosie_path);
    return FALSE;
  }
  LOG("opened librosie\n");
  return TRUE;
}

#define bind_function(localname, libname) {	\
  localname = dlsym(lib, libname);		\
  if (localname == NULL) { \
    msg = dlerror(); \
    if (msg == NULL) { msg = "no error reported"; }	   \
    LOGf("failed to bind %s, err is: %s\n", libname, msg); \
    goto fail; \
  } \
  else { \
  LOGf("bound %s\n", libname); \
  }} while (0);		       \

static int bind(void *lib){
  char *msg = NULL;
  fp_rosie_new = dlsym(lib, "rosie_new");
  if (fp_rosie_new == NULL) {
    msg = dlerror(); if (msg == NULL) msg = "no error reported";
    LOGf("failed to bind %s, err is: %s\n", "rosie_new", msg);
    goto fail;
  }

  bind_function(fp_rosie_new, "rosie_new");
  bind_function(fp_rosie_finalize, "rosie_finalize");

  bind_function(fp_rosie_new_string, "rosie_new_string");
  bind_function(fp_rosie_free_string, "rosie_free_string");
  bind_function(fp_rosie_new_string_ptr, "rosie_new_string_ptr");
  bind_function(fp_rosie_free_string_ptr, "rosie_free_string_ptr");

  bind_function(fp_rosie_setlibpath_engine, "rosie_setlibpath_engine");
  bind_function(fp_rosie_set_alloc_limit, "rosie_set_alloc_limit");
  bind_function(fp_rosie_config, "rosie_config");

  bind_function(fp_rosie_compile, "rosie_compile");
  bind_function(fp_rosie_free_rplx, "rosie_free_rplx");
  bind_function(fp_rosie_match, "rosie_match");
  bind_function(fp_rosie_matchfile, "rosie_matchfile");
  bind_function(fp_rosie_trace, "rosie_trace");

  bind_function(fp_rosie_load, "rosie_load");
  bind_function(fp_rosie_import, "rosie_import");

  LOG("Bound the librosie functions\n");
  return TRUE;

 fail:
  LOG("Failed to bind librosie functions\n");
  return FALSE;
}

static void print_usage(char *progname) {
  printf("Usage: %s [system|local] <librosie_name>\n", progname);
}

/* Main */

int main(int argc, char **argv) {

  if (argc != 3) {
    print_usage(argv[0]);
    exit(-1);
  }
  char *test_type = argv[1];
  char *librosie_path = argv[2];

  int exitStatus = 0;

  init(librosie_path);
  if (!bind(librosie)) return -1;
  char *librosie_dir = get_libdir(fp_rosie_new);
  printf("Found librosie at %s\n", librosie_dir); fflush(NULL);

  if (strncmp(test_type, "local", 6)==0) {
    if (strncmp(librosie_dir, "/usr/", 4)==0) {
      printf("ERROR: librosie was found in the system location\n");
      exit(-1);
    }
  } else if (strncmp(test_type, "system", 7)==0) {
    if (strncmp(librosie_dir, "/usr/", 4)!=0) {
      printf("ERROR: librosie was NOT found in the system location\n");
      exit(-1);
    }
  } else {
    printf("error: test type not system or local\n");
    print_usage(argv[0]);
  }


  str errors;
  void *engine = (*fp_rosie_new)(&errors);
  if (engine == NULL) {
    LOG("rosie_new failed\n");
    if (errors.ptr) LOGf("rosie_new returned: %s\n", errors.ptr);
    return -2;
  }
  LOG("obtained rosie matching engine\n");

  int err;
  int ok;
  str pkgname, as, actual_pkgname;
  pkgname = (*fp_rosie_new_string)((byte_ptr)"all", 3);
  errors = (*fp_rosie_new_string)((byte_ptr)"", 0);
  as = (*fp_rosie_new_string)((byte_ptr)"", 0);
  printf("pkgname = %.*s; as = %.*s; errors = %.*s\n",
	 pkgname.len, pkgname.ptr,
	 as.len, as.ptr,
	 errors.len, errors.ptr);
  LOG("allocated strs\n");
  err = (*fp_rosie_import)(engine, &ok, &pkgname, NULL, &actual_pkgname, &errors);
  if (err) {
    LOG("rosie call failed: import library \"all\"\n");
    exitStatus = -3;
    goto quit;
  }
  if (!ok) {
    printf("failed to import the \"all\" library with error code %d\n", ok);
    exitStatus = -4;
    goto quit;
  }

  int pat;
  str expression = STR("all.things");
  err = (*fp_rosie_compile)(engine, &expression, &pat, &errors);
  if (err) {
    LOG("rosie call failed: compile expression\n");
    exitStatus = -5;
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
    exitStatus = -6;
    goto quit;
  }

  str input = STR("1234");
  match m;
  err = (*fp_rosie_match)(engine, pat, 1, "json", &input, &m);
  if (err) {
    LOG("rosie call failed: match");
    exitStatus = -7;
    goto quit;
  }
  if (!m.data.ptr) {
    printf("match failed\n");
    exitStatus = -8;
    goto quit;
  }
  else {
    printf("match data is: %.*s\n", m.data.len, m.data.ptr);
  }

 quit:
  (*fp_rosie_finalize)(engine);
  return exitStatus;
}
