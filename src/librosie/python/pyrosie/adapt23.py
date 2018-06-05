#  -*- coding: utf-8; -*-
#  -*- Mode: Python; -*-                                                   
# 
#  adapt23.py
# 
#  © Copyright Jamie A. Jennings 2018.
#  LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
#  AUTHOR: Jamie A. Jennings

import sys

PYTHON_VERSION = None

if sys.version_info.major == 2:
    PYTHON_VERSION = 2
    str23 = lambda s: str(s)
    bytes23 = lambda s: bytes(s)
    zip23 = zip
    map23 = map
    filter23 = filter

elif sys.version_info.major == 3:
    PYTHON_VERSION = 3
    def bytes23(s):
        if isinstance(s, str):
            return bytes(s, encoding='UTF-8')
        elif isinstance(s, bytes):
            return s
        else:
            raise ValueError('obj not str or bytes: ' + repr(type(s)))
    def str23(s):
        if isinstance(s, str):
            return s
        elif isinstance(s, bytes):
            return str(s, encoding='UTF-8')
        else:
            raise ValueError('obj not str or bytes: ' + repr(type(s)))
    def zip23(*args):
        return list(zip(*args))
    def map23(fn, *args):
        return list(map(fn, *args))
    def filter23(fn, *args):
        return list(filter(fn, *args))
    
else:
    raise RuntimeError('Unexpected python major version')

