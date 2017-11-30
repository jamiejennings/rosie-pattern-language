#include <string.h>
#include <exception>
#include "include/librosiewrapper.h"

HANDLE_ERR wrap_rosie_new(str *errors) {
    HANDLE_ERR result;
    try {
        result.handle = rosie_new(errors);
    } catch(std::exception &e) {
        result.strErr = strdup(e.what());
    }
    return result;
}
