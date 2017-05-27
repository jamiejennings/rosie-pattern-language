# coding: utf-8
#  -*- Mode: Python; -*-                                              
# 
#  rtest.py     A crude sample program in Python that uses librosie
# 
#  © Copyright IBM Corporation 2016, 2017.
#  LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
#  AUTHOR: Jamie A. Jennings

# Developed using MacOSX Python 2.7.10, cffi 1.7.0
# easy_install --user cffi

import os, json, sys
import rosie

ROSIE_HOME = os.getenv("ROSIE_HOME")
if not ROSIE_HOME:
    print "Environment variable ROSIE_HOME not set.  (Must be set to the root of the rosie directory.)"
    sys.exit(-1)


Rosie = rosie.initialize(ROSIE_HOME, ROSIE_HOME + "/ffi/librosie/librosie.so")
print "Rosie library successfully loaded"

engine = Rosie.engine()
print "Obtained a rosie matching engine:", engine, "with id", engine.id

config = json.dumps( {'expression': '[:digit:]+',
                      'encode': 'json'} )
r = engine.configure(config)
if not r: print "Engine reconfigured to look for digits\n"
else: print "Error reconfiguring engine!", r

r = engine.inspect()
print r

tbl = json.loads(r[0])
print "Return from inspect_engine is:", str(tbl)

print

r = engine.load_manifest("$sys/MANIFEST")
for s in r: print s

print

def print_match_results(r):
    match = json.loads(r[0]) if r else False
    if match:
        print "Match succeeded!" 
        print "Match structure is", match
        leftover = json.loads(r[1])
        print "And there were", leftover, "unmatched characters"
    else:
        print "Match failed."
    print

start = 3        # 1-based indexing, so this starts matching at 3rd character

foo = "1239999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999";
r = engine.match(foo, start)
print_match_results(r)
        
foo = "1230000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";
r = engine.match(foo, None)
print_match_results(r)

config = json.dumps( {'expression': '(basic.network_patterns)+'} )
r = engine.configure(config)
if not r: print "Engine reconfigured to look for basic.network_patterns\n"
else: print "Error reconfiguring engine!", r

input_string = "10.0.0.1 www.ibm.com foobar@example.com"
r = engine.match(input_string, None)
print_match_results(r)

print "The next match should fail"
input_string = "this will not match a network pattern"
r = engine.match(input_string, None)
print_match_results(r)

# Repeat using eval instead
print "Calling eval on the same pattern and input, to see an explanation of the failure:"
r = engine.eval(input_string, None)
print "Results of eval are:"
for s in r: print s

engine = None

engine = Rosie.engine()
print "Obtained a rosie matching engine:", engine, "with id", engine.id

