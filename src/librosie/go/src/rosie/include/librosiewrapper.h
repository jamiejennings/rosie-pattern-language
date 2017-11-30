/*  -*- Mode: C/l; -*-                                              */
/*                                                                  */
/*  librosiewrapper.h                                               */
/*                                                                  */
/*  © Copyright IBM Corporation 2017.                               */
/*  LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)  */
/*  AUTHOR: Jamie A. Jennings                                       */

#include <stdlib.h>
#include "librosie.h"

#ifdef __cplusplus
extern "C" {
#endif
typedef struct HANDLE_ERR {
    void *handle;
    const char *strErr;
} HANDLE_ERR;

HANDLE_ERR wrap_rosie_new(str *errors);

#ifdef __cplusplus
}
#endif
     


