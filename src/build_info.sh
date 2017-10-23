#!/bin/bash

if [ "$#" -ne 3 ]; then
    echo Usage: $0 component_name build_directory compiler_name
    exit -1
fi

component=$1
dir=$2
cc=$3

echo "# Build step"
echo "COMPONENT: $component"
echo "COMPILER: $cc"
echo "BUILD_DATE: $(date)"
echo "BUILD_USER: $(whoami)"
echo "BUILD_OSTYPE: $OSTYPE"
echo "BUILD_HOSTNAME: $HOSTNAME"
echo "BUILD_PLATFORM: $((uname -o || uname -s) 2> /dev/null)"
echo "BUILD_PLATFORM_VER: $((uname -r) 2> /dev/null)"
echo "BUILD_PLATFORM_HW: $((uname -m) 2> /dev/null)"

if [ ! -d "$dir" ]; then
    echo "ERROR: BUILD_ROOT \"$dir\" not a directory"
else
    cd $dir
    echo "BUILD_ROOT: $(pwd)"
    if [ ! -d "$dir/.git" ]; then
    	echo "ERROR: GIT_REF no .git directory"
    	echo "ERROR: GIT_COMMIT no .git directory"
    else
	GIT_REF=$(git symbolic-ref -q --short HEAD || git describe --tags --exact-match)
	echo "GIT_REF: $GIT_REF"
	echo "GIT_COMMIT: $(git rev-parse --verify $GIT_REF)"
    fi
fi

    

