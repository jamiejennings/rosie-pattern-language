# RHEL 7

Below are some tips from Rosie users about how to install Rosie Pattern
Language.  Note that there is a suggested way to install prerequisite software,
such as `readline`, which may or may not be applicable to your needs or
environment.

**USE THESE TIPS AT YOUR OWN RISK**

``` 
$ cat /etc/redhat-release 
Red Hat Enterprise Linux Server release 7.2 (Maipo)
``` 


``` 
sudo yum install readline readline-devel git gcc
git clone --recursive https://github.com/jamiejennings/rosie-pattern-language.git
cd rosie-pattern-language
make
make test
sudo make install
``` 


