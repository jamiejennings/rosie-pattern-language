/*  -*- Mode: C/l; -*-                                                      */
/*                                                                          */
/*  rosie.c                                                                 */
/*                                                                          */
/*  © Copyright IBM 2018.                                                   */
/*  LICENSE: MIT License (https://opensource.org/licenses/mit-license.html) */
/*  AUTHOR: Jamie A. Jennings                                               */



#include "librosie.h"

#include <stdio.h>
#include <stdlib.h>

static const char *progname = "rosie"; /* default */

int main (int argc, char **argv) {
  str messages;

  if (argv[0] && argv[0][0]) progname = argv[0];
  printf("%s starting\n", progname);

  Engine *e = rosie_new(&messages);
  if (!e) {
    fprintf(stderr, "Error: %.*s\n", messages.len, messages.ptr);
    exit(1);
  }

  char *err;
  int status = rosie_exec_cli(e, "cli.lua", argc, argv, &err);
  if (status)
    fprintf(stderr, "Error: exec_cli returned code %d, saying: %s\n", status, err ? err : "unspecified error");

  rosie_finalize(e);
  return status;
}

