#  -*- coding: utf-8; -*-
#  -*- Mode: Python; -*-                                                   
# 
#  generic_sloc.py
# 
#  © Copyright Jamie A. Jennings 2018.
#  LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
#  AUTHOR: Jamie A. Jennings

# Example:
# python generic_sloc.py "--" ../../src/core/*.lua

import sys
if len(sys.argv) < 2:
    print("Usage: " + sys.argv[0] + " <comment_start> [files ...]")
    sys.exit(-1)

comment_start = sys.argv[1]

import rosie
engine = rosie.engine()
source_line, errs = engine.compile(bytes('!{[:space:]* "' + comment_start + '"/$}'))
if errs:
    print(str(errs))
    sys.exit(-1)

def is_source(line):
    if not line: return False
    match, leftover, abend, t0, t1 = engine.match(source_line, bytes(line), 1, b"line")
    return match and True or False

def count(f):
    count = 0
    for line in f:
        if is_source(line): count += 1
    return count

description = " non-comment, non-blank lines"

if len(sys.argv) == 2:
    print(str(count(sys.stdin)) + description)
else:
    for f in sys.argv[2:]:
        label = (f + ": " if f else "").rjust(44)
        print(label + str(count(open(f, 'r'))).rjust(4) + description)



    



                             
