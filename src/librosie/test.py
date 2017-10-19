# coding: utf-8
#  -*- Mode: Python; -*-                                              
#
# python -m unittest test
#
import unittest
import sys, os, json
import rosie

class RosieInitTest(unittest.TestCase):

    def setUp(self):
        pass

    def tearDown(self):
        pass

    def test(self):
        engine = rosie.engine(".")
        print "Rosie library successfully loaded.  Rosie matching engine:", engine
        print "Rosie is: ", rosie.lib


class RosieLoadTest(unittest.TestCase):

    engine = None
    
    def setUp(self):
        self.engine = rosie.engine(".")

    def tearDown(self):
        pass

    def test(self):
        ok, pkgname, errs = self.engine.load('package x; foo = "foo"')
        assert(ok)
        assert(pkgname == "x")
        assert(errs == None)

        b, errs = self.engine.compile("x.foo")
        assert(b[0] > 0)
        assert(errs == None)

        bb, errs = self.engine.compile("[:digit:]+")
        assert(bb[0] > 0)
        assert(errs == None)
        assert(b[0] != bb[0])

        b2, errs = self.engine.compile("[:foobar:]+")
        assert(not b2)
        errlist = json.loads(errs)
        assert(len(errlist) > 0)
        err = errlist[0]
        assert(err['message'])
        assert(err['who'] == 'compiler')

        b = None              # triggers call to librosie to gc the compiled pattern
        b, errs = self.engine.compile("[:digit:]+")
        assert(b[0] != bb[0]) # distinct values for distinct patterns
        assert(errs == None)

        num_int, errs = self.engine.compile("num.int")
        assert(not num_int)
        errlist = json.loads(errs)
        err = errlist[0]
        assert(err['message'])
        assert(err['who'] == 'compiler')
        print "Results of load():", ok, pkgname, err

        ok, pkgname, errs = self.engine.load('foo = "')
        assert(not ok)
        errlist = json.loads(errs)
        err = errlist[0]
        assert(err['message'])
        assert(err['who'] == 'parser')

        engine2 = rosie.engine(".")
        assert(engine2)
        assert(engine2 != self.engine)
        engine2 = None          # triggers call to librosie to gc the engine


class RosieConfigTest(unittest.TestCase):

    engine = None

    def setUp(self):
        self.engine = rosie.engine(".")

    def tearDown(self):
        pass

    def test(self):
        a = self.engine.config()
        assert(a)
        cfg = json.loads(a)
        for k in cfg.keys():
            if type(cfg[k]) is dict:
                assert(cfg[k]['name'])
                assert(cfg[k]['desc'])
                if not cfg[k]['value']: print "NOTE: no value for config key", cfg[k]['name']
                
class RosieMatchTest(unittest.TestCase):

    engine = None
    
    def setUp(self):
        self.engine = rosie.engine(".")

    def tearDown(self):
        pass

    def test(self):

        b, errs = self.engine.compile("[:digit:]+")
        assert(b[0] > 0)
        assert(errs == None)

        m, left, abend, tt, tm = self.engine.match(b, "321", 2, "json")
        assert(m)
        m = json.loads(m[:])
        assert(m['type'] == "*")
        assert(m['s'] == 2)     # match started at char 2
        assert(m['e'] == 4)
        assert(m['data'] == "21")
        assert(left == 0)
        assert(abend == False)
        assert(tt >= 0)
        assert(tm >= 0)

        m, left, abend, tt, tm = self.engine.match(b, "xyz", 1, "json")
        assert(m == None)
        assert(left == 3)
        assert(abend == False)
        assert(tt >= 0)
        assert(tm >= 0)

        inp = "889900112233445566778899100101102103104105106107108109110xyz"
        linp = len(inp)

        m, left, abend, tt, tm = self.engine.match(b, inp, 1, "json")
        assert(m)
        m = json.loads(m[:])
        assert(m['type'] == "*")
        assert(m['s'] == 1)
        assert(m['e'] == linp-3+1) # due to the "xyz" at the end
        assert(m['data'] == inp[0:-3])
        assert(left == 3)
        assert(abend == False)
        assert(tt >= 0)
        assert(tm >= 0)

        m, left, abend, tt, tm = self.engine.match(b, inp, 10, "json")
        assert(m)
        m = json.loads(m[:])
        assert(m['type'] == "*")
        assert(m['s'] == 10)
        assert(m['e'] == linp-3+1) # due to the "xyz" at the end
        assert(m['data'] == inp[9:-3])
        assert(left == 3)
        assert(abend == False)
        assert(tt >= 0)
        assert(tm >= 0)

        m, left, abend, tt, tm = self.engine.match(b, inp, 1, "line")
        assert(m)
        assert(m[:] == inp)
        assert(left == 3)
        assert(abend == False)
        assert(tt >= 0)
        assert(tm >= 0)

        m, left, abend, tt, tm = self.engine.match(b, inp, 1, "color")
        assert(m)
        # only checking the first two chars, looking for the start of
        # ANSI color sequence
        assert(m[0] == '\x1B')
        assert(m[1] == '[')
        assert(left == 3)
        assert(abend == False)
        assert(tt >= 0)
        assert(tm >= 0)


class RosieImportTest(unittest.TestCase):

    engine = None
    
    def setUp(self):
        self.engine = rosie.engine(".")
        assert(self.engine)

    def tearDown(self):
        pass

    def test(self):
        ok, pkgname, errs = self.engine.import_pkg('net')
        assert(ok)
        assert(pkgname == 'net')
        assert(errs == None)

        ok, pkgname, errs = self.engine.import_pkg('net', 'foobar')
        assert(ok)
        assert(pkgname == 'net') # actual name inside the package
        assert(errs == None)

        net_any, errs = self.engine.compile("net.any")
        assert(net_any)
        assert(errs == None)

        foobar_any, errs = self.engine.compile("foobar.any")
        assert(foobar_any)
        assert(errs == None)
        
        m, left, abend, tt, tm = self.engine.match(net_any, "1.2.3.4", 1, "color")
        assert(m)
        m, left, abend, tt, tm = self.engine.match(net_any, "Hello, world!", 1, "color")
        assert(not m)

        ok, pkgname, errs = self.engine.import_pkg('THISPACKAGEDOESNOTEXIST')
        assert(not ok)
        assert(errs != None)


class RosieTraceTest(unittest.TestCase):

    engine = None
    net_any = None
    
    def setUp(self):
        self.engine = rosie.engine(".")
        assert(self.engine)
        ok, pkgname, errs = self.engine.import_pkg('net')
        assert(ok)
        self.net_any, errs = self.engine.compile("net.any")
        assert(self.net_any)

    def tearDown(self):
        pass

    def test(self):
        matched, trace = self.engine.trace(self.net_any, "1.2", 1, "condensed")
        assert(matched == True)
        assert(trace)
        assert(len(trace) > 0)

        net_ip, errs = self.engine.compile("net.ip")
        assert(net_ip)
        matched, trace = self.engine.trace(net_ip, "1.2", 1, "condensed")
        assert(matched == False)
        assert(trace)
        assert(len(trace) > 0)


class RosieMatchFileTest(unittest.TestCase):

    engine = None
    net_any = None
    findall_net_any = None
    
    def setUp(self):
        self.engine = rosie.engine(".")
        assert(self.engine)
        ok, pkgname, errs = self.engine.import_pkg('net')
        assert(ok)
        self.net_any, errs = self.engine.compile("net.any")
        assert(self.net_any)
        self.findall_net_any, errs = self.engine.compile("findall:net.any")
        assert(self.findall_net_any)

    def tearDown(self):
        pass

    def test(self):
        cin, cout, cerr = self.engine.matchfile(self.findall_net_any, "json", "/etc/resolv.conf", "/tmp/resolv.out", "/tmp/resolv.err")
        print "Matchfile concluded with: ", cin, cout, cerr

        cin, cout, cerr = self.engine.matchfile(self.net_any, "color", infile="/etc/resolv.conf", errfile="/dev/null", wholefile=True)
        print "Matchfile concluded with: ", cin, cout, cerr



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
    unittest.main()
