/*  -*- Mode: C; -*-                                                         */
/*                                                                           */
/*  dynamic.c   Example client of librosie.so                                */
/*                                                                           */
/*  © Copyright IBM Corporation 2017.                                        */
/*  LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)  */
/*  AUTHOR: Jamie A. Jennings                                                */

#include <dlfcn.h>
#include <string.h>

#include "dynamic.h"

#define LIBROSIE "../librosie.so"
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


static int init(const char *librosie_path){
  librosie = dlopen(librosie_path, RTLD_NOW);
  if (librosie == NULL) {
    LOGf("failed to dlopen %s\n", librosie_path);
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

  bind_function(fp_rosie_setlibpath, "rosie_setlibpath_engine");
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



int main() {
  init(LIBROSIE);

  bind(librosie);

  str errors;
  void *engine = (*fp_rosie_new)(&errors);
  if (engine == NULL) {
    LOG("rosie_new failed\n");
    return FALSE;
  }
  LOG("obtained rosie matching engine\n");

  int err;
  int ok;
  str pkgname, as;
  pkgname = (*fp_rosie_new_string)("all", 3);
  errors = (*fp_rosie_new_string)("", 0);
  printf("pkgname = %s; as = %s; errors = %s\n", pkgname.ptr, as.ptr, errors.ptr);
  LOG("allocated strs\n");
  err = (*fp_rosie_import)(engine, &ok, &pkgname, NULL, &errors);
  if (err) {
    LOG("rosie call failed: import library \"all\"\n");
    goto quit;
  }
  if (!ok) {
    printf("failed to import the \"all\" library with error code %d\n", ok);
    goto quit;
  }

#define STR(literal) (*fp_rosie_new_string)((literal), strlen((literal)));

  int pat;
  str expression = STR("all.things");
  err = (*fp_rosie_compile)(engine, &expression, &pat, &errors);
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
  err = (*fp_rosie_match)(engine, pat, 1, "json", &input, &m);
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
    

 quit:
  (*fp_rosie_finalize)(engine);
  
}
