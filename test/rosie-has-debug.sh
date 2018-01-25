#!/bin/bash
# Returns zero exit code if the rosie binary was built with a lua repl for debugging
if [ -z "$1" ]; then
    echo "Usage: $0 <rosie-executable>"
    exit -1
else
    echo 'os.exit(0)' | "$1" -D >/dev/null
fi



