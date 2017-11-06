/*  -*- Mode: C; -*-                                                         */
/*                                                                           */
/*  test.c                                                                   */
/*                                                                           */
/*  © Copyright IBM Corporation 2017.                                        */
/*  LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)  */
/*  AUTHOR: Jamie A. Jennings                                                */

#include <dlfcn.h>

#include "librosie.h"

#define LIBROSIE_PATH "librosie.so"
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
    LOG("*** dlopen of librosie returned NULL\n");
    return FALSE;
  }
  return TRUE;
}

int main() {
  init(LIBROSIE_PATH);
  LOG("opened librosie\n");
}
