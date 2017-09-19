# coding: utf-8
#  -*- Mode: Python; -*-                                              

import sys, os, json
import rosie

ROSIE_HOME = os.getenv("ROSIE_HOME")
if not ROSIE_HOME:
    print "Environment variable ROSIE_HOME not set.  (Must be set to the root of the rosie directory.)"
    sys.exit(-1)

Rosie = rosie.initialize(ROSIE_HOME, ROSIE_HOME + "/librosie.so")
#Rosie = rosie.initialize(ROSIE_HOME, "librosie.so")
print Rosie
print "Rosie library successfully loaded"

engine = Rosie.engine()
print "Obtained a rosie matching engine:", engine


