#!/bin/bash

if [ -z $ROSIE_HOME ]; then
    echo "Creating script that sets ROSIE_HOME"
    ROSIE_HOME=`cd ../../.. && pwd`
    echo "export ROSIE_HOME=$ROSIE_HOME" >setvars
    echo "Use 'source setvars' to set ROSIE_HOME, then: python rtest.py"
else
    echo "ROSIE_HOME is already set to: $ROSIE_HOME"
    echo "Run the sample program with: python rtest.py"
fi


