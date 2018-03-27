# coding: utf-8
#  -*- Mode: Python; -*-                                              
#
# python test.py [local | system]
#
from __future__ import unicode_literals

import unittest
import sys, os, json
import rosie

# Notes
#
# (1) We use the librosie.so that is in the directory above this one,
#     i.e. "..", so we supply the librosiedir argument to
#     rosie.engine().  Normally, no argument to rosie.engine() is
#     needed.

try:
    HAS_UNICODE_TYPE = type(unicode) and True
    str23 = lambda s: str(s)
    bytes23 = lambda s: bytes(s)
except NameError:
    HAS_UNICODE_TYPE = False
    str23 = lambda s: str(s, encoding='UTF-8')
    bytes23 = lambda s: bytes(s, encoding='UTF-8')

class RosieInitTest(unittest.TestCase):

    def setUp(self):
        pass

    def tearDown(self):
        pass

    def test(self):
        engine = rosie.engine(librosiedir)
        assert(engine)

class RosieLoadTest(unittest.TestCase):

    engine = None
    
    def setUp(self):
        self.engine = rosie.engine(librosiedir)

    def tearDown(self):
        pass

    def test(self):
        ok, pkgname, errs = self.engine.load(b'package x; foo = "foo"')

        self.assertTrue(ok)
        self.assertTrue(pkgname == b"x")
        self.assertTrue(errs == None)

        b, errs = self.engine.compile(b"x.foo")
        self.assertTrue(b.valid())
        self.assertTrue(errs == None)

        bb, errs = self.engine.compile(b"[:digit:]+")
        self.assertTrue(bb.valid())
        self.assertTrue(errs == None)
        self.assertTrue(b.id[0] != bb.id[0])

        b2, errs = self.engine.compile(b"[:foobar:]+")
        self.assertTrue(not b2)
        errlist = json.loads(errs)
        self.assertTrue(len(errlist) > 0)
        err = errlist[0]
        self.assertTrue(err['message'])
        self.assertTrue(err['who'] == 'compiler')

        b = None                       # trigger call to librosie to gc the compiled pattern
        b, errs = self.engine.compile(b"[:digit:]+")
        self.assertTrue(b.id[0] != bb.id[0]) # distinct values for distinct patterns
        self.assertTrue(errs == None)

        num_int, errs = self.engine.compile(b"num.int")
        self.assertTrue(not num_int)
        errlist = json.loads(errs)
        err = errlist[0]
        self.assertTrue(err['message'])
        self.assertTrue(err['who'] == 'compiler')

        ok, pkgname, errs = self.engine.load(b'foo = "')
        self.assertTrue(not ok)
        errlist = json.loads(errs)
        err = errlist[0]
        self.assertTrue(err['message'])
        self.assertTrue(err['who'] == 'parser')

        engine2 = rosie.engine(librosiedir)
        self.assertTrue(engine2)
        self.assertTrue(engine2 != self.engine)
        engine2 = None          # triggers call to librosie to gc the engine

class RosieConfigTest(unittest.TestCase):

    engine = None

    def setUp(self):
        self.engine = rosie.engine(librosiedir)

    def tearDown(self):
        pass

    def test(self):
        a = self.engine.config()
        self.assertTrue(a)
        cfg = json.loads(a)
        array = cfg[0]
        for entry in array:
            self.assertTrue(type(entry) is dict)
            self.assertTrue(entry['name'])
            self.assertTrue(entry['description'])
            if not entry['value']: print("NOTE: no value for config key " + entry['name'])
        array = cfg[1]
        rpl_version = None
        libpath = None
        for entry in array:
            if entry['name']=='RPL_VERSION':
                rpl_version = entry['value']
            if entry['name']=='ROSIE_LIBPATH':
                libpath = entry['value']
        if HAS_UNICODE_TYPE:
            self.assertTrue(type(rpl_version) is unicode)
            self.assertTrue(type(libpath) is unicode)
        else:
            self.assertTrue(type(rpl_version) is str)
            self.assertTrue(type(libpath) is str)
            
            
class RosieLibpathTest(unittest.TestCase):

    engine = None

    def setUp(self):
        self.engine = rosie.engine(librosiedir)

    def tearDown(self):
        pass

    def test(self):
        path = self.engine.libpath()
        self.assertIsInstance(path, bytes)
        newpath = b"foo bar baz"
        self.engine.libpath(newpath)
        testpath = self.engine.libpath()
        self.assertIsInstance(testpath, bytes)
        self.assertTrue(testpath == newpath)
                
class RosieAlloclimitTest(unittest.TestCase):

    engine = None

    def setUp(self):
        self.engine = rosie.engine(librosiedir)

    def tearDown(self):
        pass

    def test(self):
        limit, usage = self.engine.alloc_limit()
        self.assertIsInstance(limit, int)
        self.assertTrue(limit == 0)
        limit, usage = self.engine.alloc_limit(0)
        limit, usage = self.engine.alloc_limit()
        self.assertTrue(limit == 0)
        limit, usage = self.engine.alloc_limit(8199)
        self.assertTrue(limit == 8199)
        with self.assertRaises(ValueError):
            limit, usage = self.engine.alloc_limit(8191) # too low
        limit, usage = self.engine.alloc_limit()
        self.assertTrue(limit == 8199)

class RosieImportTest(unittest.TestCase):

    engine = None
    
    def setUp(self):
        self.engine = rosie.engine(librosiedir)
        self.assertTrue(self.engine)

    def tearDown(self):
        pass

    def test(self):
        ok, pkgname, errs = self.engine.import_pkg(b'net')
        self.assertTrue(ok)
        self.assertTrue(pkgname == b'net')
        self.assertTrue(errs == None)

        ok, pkgname, errs = self.engine.import_pkg(b'net', b'foobar')
        self.assertTrue(ok)
        self.assertTrue(pkgname == b'net') # actual name inside the package
        self.assertTrue(errs == None)

        net_any, errs = self.engine.compile(b"net.any")
        self.assertTrue(net_any)
        self.assertTrue(errs == None)

        foobar_any, errs = self.engine.compile(b"foobar.any")
        self.assertTrue(foobar_any)
        self.assertTrue(errs == None)
        
        m, left, abend, tt, tm = self.engine.match(net_any, b"1.2.3.4", 1, b"color")
        self.assertTrue(m)
        m, left, abend, tt, tm = self.engine.match(net_any, b"Hello, world!", 1, b"color")
        self.assertTrue(not m)

        ok, pkgname, errs = self.engine.import_pkg(b'THISPACKAGEDOESNOTEXIST')
        self.assertTrue(not ok)
        self.assertTrue(errs != None)


class RosieLoadfileTest(unittest.TestCase):

    engine = None
    
    def setUp(self):
        self.engine = rosie.engine(librosiedir)
        self.assertTrue(self.engine)

    def tearDown(self):
        pass

    def test(self):
        ok, pkgname, errs = self.engine.loadfile(b'test.rpl')
        self.assertTrue(ok)
        self.assertTrue(pkgname == bytes(b'test'))
        self.assertTrue(errs == None)


class RosieMatchTest(unittest.TestCase):

    engine = None
    
    def setUp(self):
        self.engine = rosie.engine(librosiedir)

    def tearDown(self):
        pass

    def test(self):

        b, errs = self.engine.compile(b"[:digit:]+")
        self.assertTrue(b.valid())
        self.assertTrue(errs == None)

        m, left, abend, tt, tm = self.engine.match(b, b"321", 2, b"json")
        self.assertTrue(m)
        m = json.loads(bytes(m))
        self.assertTrue(m['type'] == "*")
        self.assertTrue(m['s'] == 2)     # match started at char 2
        self.assertTrue(m['e'] == 4)
        self.assertTrue(m['data'] == "21")
        self.assertTrue(left == 0)
        self.assertTrue(abend == False)
        self.assertTrue(tt >= 0)
        self.assertTrue(tm >= 0)

        m, left, abend, tt, tm = self.engine.match(b, b"xyz", 1, b"json")
        self.assertTrue(m == None)
        self.assertTrue(left == 3)
        self.assertTrue(abend == False)
        self.assertTrue(tt >= 0)
        self.assertTrue(tm >= 0)

        inp = b"889900112233445566778899100101102103104105106107108109110xyz"
        linp = len(inp)

        m, left, abend, tt, tm = self.engine.match(b, inp, 1, b"json")
        self.assertTrue(m)
        m = json.loads(m)
        self.assertTrue(m['type'] == "*")
        self.assertTrue(m['s'] == 1)
        self.assertTrue(m['e'] == linp-3+1) # due to the "xyz" at the end
        self.assertTrue(m['data'] == str23(inp[0:-3]))
        self.assertTrue(left == 3)
        self.assertTrue(abend == False)
        self.assertTrue(tt >= 0)
        self.assertTrue(tm >= 0)

        m, left, abend, tt, tm = self.engine.match(b, inp, 10, b"json")
        self.assertTrue(m)
        m = json.loads(m)
        self.assertTrue(m['type'] == "*")
        self.assertTrue(m['s'] == 10)
        self.assertTrue(m['e'] == linp-3+1) # due to the "xyz" at the end
        self.assertTrue(m['data'] == str23(inp[9:-3]))
        self.assertTrue(left == 3)
        self.assertTrue(abend == False)
        self.assertTrue(tt >= 0)
        self.assertTrue(tm >= 0)

        m, left, abend, tt, tm = self.engine.match(b, inp, 1, b"line")
        self.assertTrue(m)
        self.assertTrue(m == inp)
        self.assertTrue(left == 3)
        self.assertTrue(abend == False)
        self.assertTrue(tt >= 0)
        self.assertTrue(tm >= 0)

        m, left, abend, tt, tm = self.engine.match(b, inp, 1, b"bool")
        self.assertIs(m, True)
        self.assertTrue(left == 3)
        self.assertTrue(abend == False)
        self.assertTrue(tt >= 0)
        self.assertTrue(tm >= 0)

        m, left, abend, tt, tm = self.engine.match(b, inp, 1, b"color")
        self.assertTrue(m)
        # only checking the first two chars, looking for the start of
        # ANSI color sequence
        self.assertTrue(str23(m)[0] == '\x1B')
        self.assertTrue(str23(m)[1] == '[')
        self.assertTrue(left == 3)
        self.assertTrue(abend == False)
        self.assertTrue(tt >= 0)
        self.assertTrue(tm >= 0)

        self.assertRaises(ValueError, self.engine.match, b, inp, 1, b"this_is_not_a_valid_encoder_name")

            
class RosieTraceTest(unittest.TestCase):

    def setUp(self):
        self.engine = rosie.engine(librosiedir)
        self.assertTrue(self.engine)
        ok, pkgname, errs = self.engine.import_pkg(b'net')
        self.assertTrue(ok)
        self.net_any, errs = self.engine.compile(b'net.any')
        self.assertTrue(self.net_any)

    def tearDown(self):
        pass

    def test(self):
        matched, trace = self.engine.trace(self.net_any, b"1.2.3", 1, b"condensed")
        self.assertTrue(matched == True)
        self.assertTrue(trace)
        self.assertTrue(len(trace) > 0)

        net_ip, errs = self.engine.compile(b"net.ip")
        self.assertTrue(net_ip)
        matched, trace = self.engine.trace(net_ip, b"1.2.3", 1, b"condensed")
        self.assertTrue(matched == False)
        self.assertTrue(trace)
        self.assertTrue(len(trace) > 0)


class RosieMatchFileTest(unittest.TestCase):

    engine = None
    net_any = None
    findall_net_any = None
    
    def setUp(self):
        self.engine = rosie.engine(librosiedir)
        self.assertTrue(self.engine)
        ok, pkgname, errs = self.engine.import_pkg(b'net')
        self.assertTrue(ok)
        self.net_any, errs = self.engine.compile(b"net.any")
        self.assertTrue(self.net_any)
        self.findall_net_any, errs = self.engine.compile(b"findall:net.any")
        self.assertTrue(self.findall_net_any)

    def tearDown(self):
        pass

    def test(self):
        cin, cout, cerr = self.engine.matchfile(self.findall_net_any,
                                                b"json",
                                                b"../../../test/resolv.conf",
                                                b"/tmp/resolv.out",
                                                b"/tmp/resolv.err")
        self.assertTrue(cin == 10)
        self.assertTrue(cout == 5)
        self.assertTrue(cerr == 5)

        cin, cout, cerr = self.engine.matchfile(self.net_any,
                                                b"color",
                                                infile=b"../../../test/resolv.conf",
                                                errfile=b"/dev/null",
                                                wholefile=True)
        self.assertTrue(cin == 1)
        self.assertTrue(cout == 0)
        self.assertTrue(cerr == 1)

class RosieReadRcfileTest(unittest.TestCase):

    engine = None

    def setUp(self):
        self.engine = rosie.engine(librosiedir)

    def tearDown(self):
        pass

    def test(self):
        if testdir:
            options = self.engine.read_rcfile(bytes23(os.path.join(testdir, "rcfile1")))
            self.assertIsInstance(options, list)
            options = self.engine.read_rcfile(bytes23(os.path.join(testdir, "rcfile2")))
            self.assertTrue(options is False)
            options = self.engine.read_rcfile(b"This file does not exist")
            self.assertTrue(options is None)

class RosieExecuteRcfileTest(unittest.TestCase):

    engine = None

    def setUp(self):
        self.engine = rosie.engine(librosiedir)

    def tearDown(self):
        pass

    def test(self):
        print("*****************************************************")
        print("** Rosie errors and warnings will be printed below **")
        print("*****************************************************")
        result = self.engine.execute_rcfile(b"This file does not exist")
        self.assertTrue(result is None)
        if testdir:
            result = self.engine.execute_rcfile(bytes23(os.path.join(testdir, "rcfile1")))
            self.assertTrue(result is False)
            result = self.engine.execute_rcfile(bytes23(os.path.join(testdir, "rcfile2")))
            self.assertTrue(result is False)
            result = self.engine.execute_rcfile(bytes23(os.path.join(testdir, "rcfile3")))
            self.assertTrue(result is False)
            result = self.engine.execute_rcfile(bytes23(os.path.join(testdir, "rcfile5")))
            self.assertTrue(result is True)


        
# -----------------------------------------------------------------------------

if __name__ == '__main__':
    if len(sys.argv) != 2:
        sys.exit("Error: missing command-line parameter specifying 'local' or 'system' test")
    if sys.argv[1]=='local':
        librosiedir = "../local"
        print("Loading librosie from " + librosiedir)
        testdir = "../../../test"
    elif sys.argv[1]=='system':
        librosiedir = None
        print("Loading librosie from system library path")
        testdir = None
    else:
        sys.exit("Error: invalid command-line parameter (must be 'local' or 'system')")
    print("Running tests using " + sys.argv[1] + " rosie installation")
    del sys.argv[1:]
    unittest.main()
    
