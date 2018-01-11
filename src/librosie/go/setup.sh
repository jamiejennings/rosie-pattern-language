#!/bin/bash
echo "Creating script that sets GOPATH and ROSIE_HOME"
echo "export GOPATH=`pwd`" >setvars

LIB=`cd .. && pwd`
LUALIB=`cd ../../../submodules/lua/include && pwd`
RPEGLIB=`cd ../../../submodules/rosie-lpeg/src && pwd`

echo "Creating 'include' directory in 'src/rtest' and symlinks to librosie source"
mkdir -p src/rtest/include
ln -fs $LIB/librosie.h src/rosie/include/
ln -fs $RPEGLIB/rpeg.h src/rosie/include/
ln -fs $RPEGLIB/rbuf.h src/rosie/include/
ln -fs $LUALIB/luaxlib.h src/rosie/include/

echo "Linking librosie.a from librosie directory"
ln -fs $LIB/librosie.a src/rosie/librosie.a

if [ -z $ROSIE_HOME ]; then
    ROSIE_HOME=`cd ../../.. && pwd`
    echo "ROSIE_HOME not set.  Assuming rosie installation is $ROSIE_HOME"
else
    echo "ROSIE_HOME is already set to: $ROSIE_HOME"
fi
if [ ! -d rosie ]; then
    echo "Creating link 'rosie' to rosie installation directory"
    ln -fs $ROSIE_HOME rosie
else
    echo "Link 'rosie' to rosie installation directory already exists"
fi


echo "--------------------------------------------------------"
echo "Source the file 'setvars' to set GOPATH and ROSIE_HOME:"
echo '. setvars'
echo "go build rtest"
echo "./rtest"






