/*  -*- Mode: C/l; -*-                                                      */
/*                                                                          */
/*  rosie.c                                                                 */
/*                                                                          */
/*  © Copyright IBM 2018.                                                   */
/*  LICENSE: MIT License (https://opensource.org/licenses/mit-license.html) */
/*  AUTHOR: Jamie A. Jennings                                               */

#include "librosie.h"

#include <stdio.h>
#include <string.h>
#include <stdlib.h>

static const char *progname = "rosie"; /* default */

int main (int argc, char **argv) {
  str messages;
  int invoke_repl = 0;

  if (argv[0] && argv[0][0]) progname = argv[0];

  Engine *e = rosie_new(&messages);
  if (!e) {
    fprintf(stderr, "Error: %.*s\n", messages.len, messages.ptr);
    exit(1);
  }

  if ((argc > 0) && argv[1] && !strncmp(argv[1], "-D", 3)) {
    invoke_repl = 1;
    for (int i = 1; i < argc-1; i++) argv[i] = argv[i+1];
    argv[argc-1] = (char *)'\0';
    argc = argc - 1;
  }

  char *err;
  int status = rosie_exec_cli(e, argc, argv, &err);
  if (status)
    fprintf(stderr, "%s: exec_cli returned code %d, saying: %s\n",
	    progname,
	    status,
	    err ? err : "unspecified error");

  if (invoke_repl) {
#ifdef LUADEBUG
    printf("Entering %s\n", LUA_COPYRIGHT);
    rosie_exec_lua_repl(e, argc, argv);
#else
    fprintf(stderr, "%s: no lua debug support available\n", progname);
#endif
  }

  rosie_finalize(e);
  return status;
}

