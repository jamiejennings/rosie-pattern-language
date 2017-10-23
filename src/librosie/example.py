import rosie
engine = rosie.engine()   # or rosie.engine(librosiedir) if using a local (non-system) installation
ok, pkgname, errs = engine.import_pkg('net')
net_any, errs = engine.compile("net.any")

match, leftover, abend, t0, t1 = engine.match(net_any, "1.2.3.4", 1, "color")
if leftover != 0: print "There were", leftover, "characters left over"
print "Match was:", match


