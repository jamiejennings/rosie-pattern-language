#include "librosie.h"
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <errno.h>

errno_t actual_file(char *inpath, char **outpath) {
  char *in = malloc((size_t) MAXPATHLEN);
  char *out = alloca((size_t) MAXPATHLEN);
  strncpy(in, inpath, MAXPATHLEN);
  int n = 0;
  while (n != -1) {
    n = readlink(in, out, MAXPATHLEN);
    if (n != -1) {
      strncpy(in, out, n);
      in[n] = '\0';
    }
  }
  if (errno == EINVAL) {
    *outpath = in;
    return 0;
  }
  free(in); 
  return errno; 
}

int main(int argc, char **argv) {
  char *af;
  if (argc < 2) printf("Usage: %s <filename>\n", argv[0]);
  else {
    errno_t err = actual_file(argv[1], &af);
    if (err) exit(err);
    else printf("%s\n", af);
  }
  return 0;
}
