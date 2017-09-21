#!/bin/bash

dir=$1
cc=$2

echo "BUILD_DATE $(date)"
echo "BUILD_USER $(whoami)"
echo "BUILD_DIR $(pwd)"
echo "BUILD_PLATFORM $((uname -o || uname -s) 2> /dev/null)"
echo "BUILD_PLATFORM_VER $((uname -r) 2> /dev/null)"
echo "BUILD_PLATFORM_HW $((uname -m) 2> /dev/null)"
echo "COMPILER $cc"

if [ ! -d "$dir" ]; then
    echo "BUILD_ROOT ERROR \"$dir\" not a directory"
else
    cd $dir
    echo "BUILD_ROOT $(pwd)"
    if [ ! -d "$dir/.git" ]; then
    	echo "GIT_BRANCH ERROR no .git directory"
    	echo "GIT_COMMIT ERROR no .git directory"
    else
	echo "GIT_BRANCH $(git symbolic-ref --short -q HEAD)"
	echo "GIT_COMMIT $(git rev-parse --verify $(git symbolic-ref HEAD))"
    fi
fi

    

