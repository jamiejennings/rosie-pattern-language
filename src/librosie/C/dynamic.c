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


/* RTLD_GLOBAL needed on Ubuntu, but not Fedora/Centos/Arch family.  Why? */
static int init(const char *librosie_path){
  librosie = dlopen(librosie_path, RTLD_NOW | RTLD_GLOBAL);
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

/* Main */

int main(int argc, char **argv) {

  if (argc != 2) {
    printf("Usage: %s <full_path_for_librosie>\n", argv[0]);
    exit(-1);
  }
  char *librosie_path = argv[1];

  int exitStatus = 0;

  init(librosie_path);

  if (!bind(librosie)) return -1;

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
  printf("pkgname = %s; as = %s; errors = %s\n", pkgname.ptr, as.ptr, errors.ptr);
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

#define STR(literal) (*fp_rosie_new_string)((byte_ptr)(literal), strlen((literal)));

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
