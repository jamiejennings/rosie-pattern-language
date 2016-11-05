#Ubuntu 16

Below are some tips from Rosie users about how to install Rosie Pattern
Language.  Note that there is a suggested way to install prerequisite software,
such as `readline`, which may or may not be applicable to your needs or
environment.

**USE THESE TIPS AT YOUR OWN RISK**

``` 
$ lsb_release -d
Description:	Ubuntu 16.04.1 LTS
```


``` 
sudo apt install libreadline6 libreadline6-dev
git clone --recursive https://github.com/jamiejennings/rosie-pattern-language.git
make
make test
sudo make install
``` 


