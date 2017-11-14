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
#include "../../../submodules/rosie-lpeg/src/rpeg.h"

typedef struct rosie_string str;

typedef struct rosie_matchresult {
     str data;
     int leftover;
     int abend;
     int ttotal;
     int tmatch;
} match;

void *(*fp_rosie_new)();
str   (*fp_rosie_new_string)();
void  (*fp_rosie_free_string)();
str   (*fp_rosie_new_string_ptr)();
void  (*fp_rosie_free_string_ptr)();
void  (*fp_rosie_finalize)();
int   (*fp_rosie_setlibpath)();
int   (*fp_rosie_set_alloc_limit)();
int   (*fp_rosie_config)();
int   (*fp_rosie_compile)();
int   (*fp_rosie_free_rplx)();
int   (*fp_rosie_match)();
int   (*fp_rosie_matchfile)();
int   (*fp_rosie_trace)();
int   (*fp_rosie_load)();
int   (*fp_rosie_import)();

/* REFERENCE:
str rosie_new_string(byte_ptr msg, size_t len);
str *rosie_new_string_ptr(byte_ptr msg, size_t len);
void rosie_free_string(str s);
void rosie_free_string_ptr(str *s);

void *rosie_new(str *errors);
void rosie_finalize(void *L);
int rosie_setlibpath(void *L, char *newpath);
int rosie_set_alloc_limit(void *L, int newlimit);
int rosie_config(void *L, str *retvals);
int rosie_compile(void *L, str *expression, int *pat, str *errors);
int rosie_free_rplx(void *L, int pat);
int rosie_match(void *L, int pat, int start, char *encoder, str *input, match *match);
int rosie_matchfile(void *L, int pat, char *encoder, int wholefileflag,
		    char *infilename, char *outfilename, char *errfilename,
		    int *cin, int *cout, int *cerr,
		    str *err);
int rosie_trace(void *L, int pat, int start, char *trace_style, str *input, int *matched, str *trace);
int rosie_load(void *L, int *ok, str *src, str *pkgname, str *errors);
int rosie_import(void *L, int *ok, str *pkgname, str *as, str *errors);
*/
