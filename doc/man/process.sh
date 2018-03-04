#!/bin/bash
today=`date "+%Y-%m-%d"`
ronn --style="./man.css" --organization="The Rosie Project" "$@"
