The Go client here is currently broken.  To reproduce the problem:

```shell 
git clone https://github.com/jamiejennings/rosie-pattern-language.git
cd rosie-pattern-language
git checkout goclient
make
cd src/librosie/go
./setup.sh
. setvars
go build rtest
./rtest
```

Then observe something like this:

```shell 
$ ./rtest
Initializing Rosie... Engine is &{0x43027b0}
And another engine: &{0x4522540}
Finalizing engine  &{0x43027b0}
Engine is &{0x4522540}
ROSIE_VERSION = 1.0.0-alpha-8 (version of rosie cli/api)
ROSIE_HOME = /Users/jennings/Projects/rosie-pattern-language/src/librosie/go/./rosie (location of the rosie installation directory)
ROSIE_DEV = true (true if rosie was started in development mode)
ROSIE_LIBDIR = /Users/jennings/Projects/rosie-pattern-language/src/librosie/go/./rosie/rpl (location of the standard rpl library)
ROSIE_LIBPATH = /Users/jennings/Projects/rosie-pattern-language/src/librosie/go/./rosie/rpl (directories to search for modules)
ROSIE_LIBPATH_SOURCE = lib (how ROSIE_LIBPATH was set: lib/env/cli/api)
RPL_VERSION = 1.1 (version of rpl (language) accepted)
HOSTTYPE =  (type of host on which rosie is running)
OSTYPE =  (type of OS on which rosie is running)
ROSIE_COMMAND =  (invocation command, if rosie invoked through the CLI)
fatal: morestack on g0
SIGTRAP: trace trap
PC=0x40515f2 m=6 sigcode=1
signal arrived during cgo execution

goroutine 1 [syscall, locked to thread]:
runtime.cgocall(0x40bae30, 0xc420036d50, 0x0)
	/usr/local/go/src/runtime/cgocall.go:132 +0xe4 fp=0xc420036d20 sp=0xc420036ce0 pc=0x4003724
rosie._Cfunc_rosie_compile(0x4522540, 0x46ce100, 0x46cb3e0, 0x46c4960, 0x0)
	rosie/_obj/_cgo_gotypes.go:150 +0x4d fp=0xc420036d50 sp=0xc420036d20 pc=0x40b93cd
rosie.(*Engine).Compile.func1(0x4522540, 0x46ce100, 0x46cb3e0, 0x46c4960, 0x1)
	/Users/jennings/Projects/rosie-pattern-language/src/librosie/go/src/rosie/rosie.go:123 +0xec fp=0xc420036d88 sp=0xc420036d50 pc=0x40ba1fc
rosie.(*Engine).Compile(0xc42000e038, 0x411e357, 0xa, 0x3, 0x3, 0x48)
	/Users/jennings/Projects/rosie-pattern-language/src/librosie/go/src/rosie/rosie.go:123 +0x9e fp=0xc420036dd8 sp=0xc420036d88 pc=0x40b9dfe
main.main()
	/Users/jennings/Projects/rosie-pattern-language/src/librosie/go/src/rtest/rtest.go:56 +0x365 fp=0xc420036f80 sp=0xc420036dd8 pc=0x40ba6a5
runtime.main()
	/usr/local/go/src/runtime/proc.go:195 +0x226 fp=0xc420036fe0 sp=0xc420036f80 pc=0x402bcc6
runtime.goexit()
	/usr/local/go/src/runtime/asm_amd64.s:2337 +0x1 fp=0xc420036fe8 sp=0xc420036fe0 pc=0x4053f21

rax    0x17
rbx    0xc42002d180
rcx    0x4054e75
rdx    0x0
rdi    0x2
rsi    0x41205ec
rbp    0x700007ed6840
rsp    0x700007e16790
r8     0x5826c28
r9     0x42d4770
r10    0x700007ed6890
r11    0x206
r12    0x6
r13    0x5000008
r14    0x46b4768
r15    0x700007ed6890
rip    0x40515f2
rflags 0x206
cs     0x2b
fs     0x0
gs     0x0
$ 
```

My system:

```shell 
$ go version
go version go1.9.2 darwin/amd64
$ uname -a
Darwin Jamies-Compabler.local 17.3.0 Darwin Kernel Version 17.3.0: Thu Nov  9 18:09:22 PST 2017; root:xnu-4570.31.3~1/RELEASE_X86_64 x86_64
$
```

