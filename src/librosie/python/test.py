# coding: utf-8
#  -*- Mode: Python; -*-                                              
#
# python test.py [local | system]
#
import unittest
import sys, os, json
import rosie

# For unit testing:
# (1) We use the librosie.so that is in the directory above this one, i.e. "..".
#     Normally, no argument to rosie.engine() is needed.
# (2) librosie will look for the rosie installation in the 'rosie' directory alongside
#     it, so there must be a link 'rosie -> ../..' in the same directory as this
#     test file.

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
        ok, pkgname, errs = self.engine.load('package x; foo = "foo"')
        self.assertTrue(ok)
        self.assertTrue(pkgname == "x")
        self.assertTrue(errs == None)

        b, errs = self.engine.compile("x.foo")
        self.assertTrue(b[0] > 0)
        self.assertTrue(errs == None)

        bb, errs = self.engine.compile("[:digit:]+")
        self.assertTrue(bb[0] > 0)
        self.assertTrue(errs == None)
        self.assertTrue(b[0] != bb[0])

        b2, errs = self.engine.compile("[:foobar:]+")
        self.assertTrue(not b2)
        errlist = json.loads(errs)
        self.assertTrue(len(errlist) > 0)
        err = errlist[0]
        self.assertTrue(err['message'])
        self.assertTrue(err['who'] == 'compiler')

        b = None              # triggers call to librosie to gc the compiled pattern
        b, errs = self.engine.compile("[:digit:]+")
        self.assertTrue(b[0] != bb[0]) # distinct values for distinct patterns
        self.assertTrue(errs == None)

        num_int, errs = self.engine.compile("num.int")
        self.assertTrue(not num_int)
        errlist = json.loads(errs)
        err = errlist[0]
        self.assertTrue(err['message'])
        self.assertTrue(err['who'] == 'compiler')

        ok, pkgname, errs = self.engine.load('foo = "')
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
        for entry in cfg:
            self.assertTrue(type(entry) is dict)
            self.assertTrue(entry['name'])
            self.assertTrue(entry['desc'])
            if not entry['value']: print "NOTE: no value for config key", entry['name']
                
class RosieMatchTest(unittest.TestCase):

    engine = None
    
    def setUp(self):
        self.engine = rosie.engine(librosiedir)

    def tearDown(self):
        pass

    def test(self):

        b, errs = self.engine.compile("[:digit:]+")
        self.assertTrue(b[0] > 0)
        self.assertTrue(errs == None)

        m, left, abend, tt, tm = self.engine.match(b, "321", 2, "json")
        self.assertTrue(m)
        m = json.loads(m[:])
        self.assertTrue(m['type'] == "*")
        self.assertTrue(m['s'] == 2)     # match started at char 2
        self.assertTrue(m['e'] == 4)
        self.assertTrue(m['data'] == "21")
        self.assertTrue(left == 0)
        self.assertTrue(abend == False)
        self.assertTrue(tt >= 0)
        self.assertTrue(tm >= 0)

        m, left, abend, tt, tm = self.engine.match(b, "xyz", 1, "json")
        self.assertTrue(m == None)
        self.assertTrue(left == 3)
        self.assertTrue(abend == False)
        self.assertTrue(tt >= 0)
        self.assertTrue(tm >= 0)

        inp = "889900112233445566778899100101102103104105106107108109110xyz"
        linp = len(inp)

        m, left, abend, tt, tm = self.engine.match(b, inp, 1, "json")
        self.assertTrue(m)
        m = json.loads(m[:])
        self.assertTrue(m['type'] == "*")
        self.assertTrue(m['s'] == 1)
        self.assertTrue(m['e'] == linp-3+1) # due to the "xyz" at the end
        self.assertTrue(m['data'] == inp[0:-3])
        self.assertTrue(left == 3)
        self.assertTrue(abend == False)
        self.assertTrue(tt >= 0)
        self.assertTrue(tm >= 0)

        m, left, abend, tt, tm = self.engine.match(b, inp, 10, "json")
        self.assertTrue(m)
        m = json.loads(m[:])
        self.assertTrue(m['type'] == "*")
        self.assertTrue(m['s'] == 10)
        self.assertTrue(m['e'] == linp-3+1) # due to the "xyz" at the end
        self.assertTrue(m['data'] == inp[9:-3])
        self.assertTrue(left == 3)
        self.assertTrue(abend == False)
        self.assertTrue(tt >= 0)
        self.assertTrue(tm >= 0)

        m, left, abend, tt, tm = self.engine.match(b, inp, 1, "line")
        self.assertTrue(m)
        self.assertTrue(m[:] == inp)
        self.assertTrue(left == 3)
        self.assertTrue(abend == False)
        self.assertTrue(tt >= 0)
        self.assertTrue(tm >= 0)

        m, left, abend, tt, tm = self.engine.match(b, inp, 1, "color")
        self.assertTrue(m)
        # only checking the first two chars, looking for the start of
        # ANSI color sequence
        self.assertTrue(m[0] == '\x1B')
        self.assertTrue(m[1] == '[')
        self.assertTrue(left == 3)
        self.assertTrue(abend == False)
        self.assertTrue(tt >= 0)
        self.assertTrue(tm >= 0)

class RosieImportTest(unittest.TestCase):

    engine = None
    
    def setUp(self):
        self.engine = rosie.engine(librosiedir)
        self.assertTrue(self.engine)

    def tearDown(self):
        pass

    def test(self):
        ok, pkgname, errs = self.engine.import_pkg('net')
        self.assertTrue(ok)
        self.assertTrue(pkgname == 'net')
        self.assertTrue(errs == None)

        ok, pkgname, errs = self.engine.import_pkg('net', 'foobar')
        self.assertTrue(ok)
        self.assertTrue(pkgname == 'net') # actual name inside the package
        self.assertTrue(errs == None)

        net_any, errs = self.engine.compile("net.any")
        self.assertTrue(net_any)
        self.assertTrue(errs == None)

        foobar_any, errs = self.engine.compile("foobar.any")
        self.assertTrue(foobar_any)
        self.assertTrue(errs == None)
        
        m, left, abend, tt, tm = self.engine.match(net_any, "1.2.3.4", 1, "color")
        self.assertTrue(m)
        m, left, abend, tt, tm = self.engine.match(net_any, "Hello, world!", 1, "color")
        self.assertTrue(not m)

        ok, pkgname, errs = self.engine.import_pkg('THISPACKAGEDOESNOTEXIST')
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
        ok, pkgname, errs = self.engine.loadfile('test.rpl')
        self.assertTrue(ok)
        self.assertTrue(pkgname == 'test')
        self.assertTrue(errs == None)
        

class RosieTraceTest(unittest.TestCase):

    engine = None
    net_any = None
    
    def setUp(self):
        self.engine = rosie.engine(librosiedir)
        self.assertTrue(self.engine)
        ok, pkgname, errs = self.engine.import_pkg('net')
        self.assertTrue(ok)
        self.net_any, errs = self.engine.compile("net.any")
        self.assertTrue(self.net_any)

    def tearDown(self):
        pass

    def test(self):
        matched, trace = self.engine.trace(self.net_any, "1.2", 1, "condensed")
        self.assertTrue(matched == True)
        self.assertTrue(trace)
        self.assertTrue(len(trace) > 0)

        net_ip, errs = self.engine.compile("net.ip")
        self.assertTrue(net_ip)
        matched, trace = self.engine.trace(net_ip, "1.2", 1, "condensed")
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
        ok, pkgname, errs = self.engine.import_pkg('net')
        self.assertTrue(ok)
        self.net_any, errs = self.engine.compile("net.any")
        self.assertTrue(self.net_any)
        self.findall_net_any, errs = self.engine.compile("findall:net.any")
        self.assertTrue(self.findall_net_any)

    def tearDown(self):
        pass

    def test(self):
        cin, cout, cerr = self.engine.matchfile(self.findall_net_any, "json", "../../../test/resolv.conf", "/tmp/resolv.out", "/tmp/resolv.err")
        self.assertTrue(cin == 10)
        self.assertTrue(cout == 5)
        self.assertTrue(cerr == 5)

        cin, cout, cerr = self.engine.matchfile(self.net_any, "color", infile="../../../test/resolv.conf", errfile="/dev/null", wholefile=True)
        self.assertTrue(cin == 1)
        self.assertTrue(cout == 0)
        self.assertTrue(cerr == 1)


# set soft memory limit also

# engine.setlibpath("/tmp")
# print(engine.config())

# ok, pkgname, errs = engine.import_pkg("fooword")
# print "importing word while libpath is set to /tmp produced:", ok, pkgname, errs

# bar, errs = engine.compile("word.bar")
# print "Compiling word.bar produced:", bar, "holding", bar[0], "and", errs

# m, left, abend, tt, tm = engine.match(bar, "Hi", 1, "line")
# print m, left, abend, tt, tm


if __name__ == '__main__':
    if len(sys.argv) != 2:
        sys.exit("Error: missing command-line parameter specifying 'local' or 'system' test")
    if sys.argv[1]=='local':
        librosiedir = ".."
        print "Loading librosie from", librosiedir
    elif sys.argv[1]=='system':
        librosiedir = None
        print "Loading librosie from system library path"
    else:
        sys.exit("Error: invalid command-line parameter (must be 'local' or 'system')")
    print "Running tests using", sys.argv[1], "rosie installation"
    del sys.argv[1:]
    unittest.main()
    
