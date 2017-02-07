#!/bin/bash

echo "Creating script that sets ROSIE_HOME (and CXX for OS X)"
echo -n >setvars

REPORTED_PLATFORM=`(uname -o || uname -s) 2> /dev/null`
if [ $REPORTED_PLATFORM = "Darwin" ]; then
    PLATFORM=macosx
elif [ $REPORTED_PLATFORM = "GNU/Linux" ]; then
    PLATFORM=linux
else
    PLATFORM=none
fi

LIB=`cd ../../librosie && pwd`
echo "Making link to 'librosie.so'"
ln -fs $LIB/librosie.so .

if [ $PLATFORM = "macosx" ]; then
    echo "export CXX=clang++" >>setvars
    echo "Creating dSYM version of librosie.so"
    dsymutil librosie.so
fi

if [ -z $ROSIE_HOME ]; then
    ROSIE_HOME=`cd ../../.. && pwd`
    echo "export ROSIE_HOME=$ROSIE_HOME" >>setvars
else
    echo "ROSIE_HOME is already set to: $ROSIE_HOME"
fi

echo "Do 'source setvars', then run sample program with: node rtest.js"
echo "  (If nodejs prereqs are not installed, do: npm install debug ref-array ffi)"
