#!/bin/bash
echo Resetting GOPATH to current directory
echo "export GOPATH=`pwd`" >setgopath

LIB=`cd ../../librosie && pwd`
echo "Linking to 'librosie.c' in 'src/rtest'"
ln -fs $LIB/librosie.c src/rtest/librosie.c

echo "Creating 'include' directory in 'src/rtest' and symlinks to librosie source"
mkdir -p src/rtest/include
ln -fs $LIB/librosie.h src/rtest/include/librosie.h
ln -fs $LIB/librosie_gen.h src/rtest/include/librosie_gen.h
ln -fs $LIB/librosie_gen.c src/rtest/include/librosie_gen.c

echo "Creating 'libs' directory in 'src/rtest' and symlink to liblua"
LIB=`cd ../../../tmp/lua-5.3.2/src && pwd`
mkdir -p src/rtest/libs
ln -fs $LIB/liblua.a src/rtest/libs/liblua.a

echo "Use 'source setgopath' to set '$GOPATH' to the current directory, then:"
echo "go build rtest"
echo "./rtest"





