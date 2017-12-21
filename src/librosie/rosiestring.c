/*  -*- Mode: C/l; -*-                                                       */
/*                                                                           */
/*  rosiestring.c  Part of librosie.c                                        */
/*                                                                           */
/*  © Copyright Jamie A. Jennings 2017.                                      */
/*  LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)  */
/*  AUTHOR: Jamie A. Jennings                                                */


/* Constant strings are statically allocated in C, so there is no need
 * to copy one in order to return a pointer to it.  However, our API
 * policy is that the client must call rosie_free_string(messages)
 * when librosie returns a non-NULL messages.ptr.  It is an error to
 * free a statically allocated string, so we are forced to (malloc) a
 * copy to return to the client.
 */
static str rosie_new_string_from_const(const char *msg) {
  size_t len = strlen(msg);
  return rosie_new_string((byte_ptr) msg, len);
}

/* Caller must ensure liveness of msg.  Typically, msg must be
 * allocated on the heap.
 */
str rosie_string_from(byte_ptr msg, size_t len) {
  str retval;
  retval.len = len;
  retval.ptr = msg;
  return retval;
}

/* Copies msg into heap-allocated storage */
str rosie_new_string(byte_ptr msg, size_t len) {
  byte_ptr new = malloc(len);
  if (!new) {
    display("Out of memory (new0)");
    return rosie_string_from(NULL, 0);
  }
  memcpy((char *)new, msg, len);
  return rosie_string_from(new, len);
}

str *rosie_new_string_ptr(byte_ptr msg, size_t len) {
  str temp = rosie_new_string(msg, len);
  str *retval = malloc(sizeof(str));
  if (!retval) {
    display("Out of memory (new2)");
    return NULL;
  }
  retval->len = temp.len;
  retval->ptr = temp.ptr;
  return retval;
}     

void rosie_free_string_ptr(str *ref) {
     free(ref->ptr);
     free(ref);
}

void rosie_free_string(str s) {
     free(s.ptr);
}

