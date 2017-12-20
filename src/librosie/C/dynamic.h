/*  -*- Mode: C/l; -*-                                                       */
/*                                                                           */
/*  dynamic.h                                                                */
/*                                                                           */
/*  © Copyright IBM Corporation 2017.                                        */
/*  LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)  */
/*  AUTHOR: Jamie A. Jennings                                                */

#define INITIAL_RPLX_SLOTS 32
#define INITIAL_ALLOC_LIMIT_MB 0
#define MIN_ALLOC_LIMIT_MB 10

#define TRUE 1
#define FALSE 0

#define MAX_ENCODER_NAME_LENGTH 64 /* arbitrary limit to avoid runaway strcmp */

#define SUCCESS 0
#define ERR_OUT_OF_MEMORY -2
#define ERR_SYSCALL_FAILED -3
#define ERR_ENGINE_CALL_FAILED -4

/* These codes are returned in the length field of an str whose ptr is NULL */
#define ERR_NO_MATCH 0
#define ERR_NO_PATTERN 1
#define ERR_NO_TRACESTYLE 2	/* same as no encoder */
#define ERR_NO_FILE 3		/* no such file or directory */

#include <stdint.h>
#include <sys/param.h>		/* MAXPATHLEN */

#ifdef __cplusplus
extern "C" {
#endif
#include "../../../submodules/rosie-lpeg/src/rpeg.h"
#ifdef __cplusplus
}
#endif

typedef struct rosie_string str;

typedef struct rosie_matchresult {
     str data;
     int leftover;
     int abend;
     int ttotal;
     int tmatch;
} match;

str (*fp_rosie_new_string)(byte_ptr msg, size_t len);
str *(*fp_rosie_string_ptr_from)(byte_ptr msg, size_t len);
void (*fp_rosie_free_string)(str s);
void (*fp_rosie_free_string_ptr)(str *s);

void *(*fp_rosie_new)(str *errors);
void (*fp_rosie_finalize)(void *L);
int (*fp_rosie_setlibpath_engine)(void *L, char *newpath);
int (*fp_rosie_set_alloc_limit)(void *L, int newlimit);
int (*fp_rosie_config)(void *L, str *retvals);
int (*fp_rosie_compile)(void *L, str *expression, int *pat, str *errors);
int (*fp_rosie_free_rplx)(void *L, int pat);
int (*fp_rosie_match)(void *L, int pat, int start, char *encoder, str *input, match *match);
int (*fp_rosie_matchfile)(void *L, int pat, char *encoder, int wholefileflag,
		    char *infilename, char *outfilename, char *errfilename,
		    int *cin, int *cout, int *cerr,
		    str *err);
int (*fp_rosie_trace)(void *L, int pat, int start, char *trace_style, str *input, int *matched, str *trace);
int (*fp_rosie_load)(void *L, int *ok, str *src, str *pkgname, str *errors);
int (*fp_rosie_import)(void *L, int *ok, str *pkgname, str *as, str *errors);

