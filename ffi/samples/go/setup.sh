#!/bin/bash
echo "Creating script that sets GOPATH and ROSIE_HOME"
echo "export GOPATH=`pwd`" >setvars

LIB=`cd ../../librosie && pwd`

echo "Creating 'include' directory in 'src/rtest' and symlinks to librosie source"
mkdir -p src/rtest/include
ln -fs $LIB/librosie.h src/rtest/include/librosie.h
ln -fs $LIB/librosie_gen.h src/rtest/include/librosie_gen.h
ln -fs $LIB/librosie_gen.c src/rtest/include/librosie_gen.c

echo "Linking librosie.a from librosie directory"
ln -fs $LIB/librosie.a src/rtest/librosie.a

if [ -z $ROSIE_HOME ]; then
    ROSIE_HOME=`cd ../../.. && pwd`
    echo "export ROSIE_HOME=$ROSIE_HOME" >>setvars
else
    echo "ROSIE_HOME is already set to: $ROSIE_HOME"
fi

echo "Use 'source setvars' to set GOPATH and ROSIE_HOME, then:"
echo "go build rtest"
echo "./rtest"






