# coding: utf-8
#  -*- Mode: Python; -*-                                              
# 
#  jsontest.py     A sample program in Python that uses librosie
# 
#  © Copyright IBM Corporation 2017.
#  LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
#  AUTHOR: Jamie A. Jennings

# Developed using MacOSX Python 2.7.10, cffi 1.7.0
# easy_install --user cffi

import sys, os, json
import rosie

Rosie = rosie.initialize()

engine = Rosie.engine()

r = engine.load_file("$sys/rpl/common.rpl")
r = engine.load_file("$sys/rpl/json.rpl")

config = json.dumps( {'expression': 'json.discard',
                      'encode': 'json'} )

r = engine.configure(config)
if r: print r

def print_match_results(r):
    match = json.loads(r[0]) if r else False
    if match:
        sys.stderr.write("Match succeeded!\n")
        #print "Match structure is", match
        leftover = json.loads(r[1])
        sys.stderr.write("There were " + str(leftover) + " unmatched characters\n")
    else:
        print "Match failed."
    print

#f = open(Rosie.rosie_home + '/test/json-test-input.json', 'r')
f = open(Rosie.rosie_home + '/test/large-generated.json', 'r')
input = f.read()

r = engine.match(input, 1)
print_match_results(r)
        

