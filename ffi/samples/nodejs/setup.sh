#!/bin/bash


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
    echo "Creating dSYM version of librosie.so"
    dsymutil librosie.so
fi

if [ -z $ROSIE_HOME ]; then
    echo "Creating script that sets ROSIE_HOME"
    ROSIE_HOME=`cd ../../.. && pwd`
    echo "export ROSIE_HOME=$ROSIE_HOME" >setvars
    echo "Use 'source setvars' to set ROSIE_HOME, then: node rtest.js"
else
    echo "ROSIE_HOME is already set to: $ROSIE_HOME"
    echo "Run the sample program with: node rtest.js"
fi

