#!/bin/bash
# gem install --user-install ronn
ronn --style="./man.css" --organization="The Rosie Project" "$@"
