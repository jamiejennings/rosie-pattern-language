#!/bin/bash

LIB=`cd ../../librosie && pwd`
echo "Making link to 'librosie.so'"
ln -fs $LIB/librosie.so .
