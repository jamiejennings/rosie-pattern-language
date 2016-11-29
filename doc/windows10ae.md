# Windows 10 Anniversay Edition

Below are some tips from Rosie users about how to install Rosie Pattern
Language.  Note that there is a suggested way to install prerequisite software,
such as `readline`, which may or may not be applicable to your needs or
environment.

**USE THESE TIPS AT YOUR OWN RISK**

It turns out that when you install the unix `bash` shell on Windows 10
"Anniversary Edition", you get a "subsystem for Linux".  You're now running
`bash` on Ubuntu Linux on Windows.  This makes it easy to install and use Rosie
by following the Ubuntu tips.

1. [Install bash on Windows](https://msdn.microsoft.com/en-us/commandline/wsl/install_guide)

2. Download pre-req packages `gcc` and `make` on the Ubuntu 14.04 user-mode
image that has been downloaded on Windows by the previous step:

	 ```
	 sudo apt-get install gcc
	 sudo apt-get install make
	 ```

3. Although the steps above install Ubuntu 14 on Windows,
   the instructions given here work the same way they work on Ubuntu 16:
   [Rosie install tips for Ubuntu 16](https://github.com/jamiejennings/rosie-pattern-language/blob/master/doc/ubuntu.md)

4. To access files on the Windows filesystem, navigate to `/mnt` directory from
the bash shell where all the windows drives are mounted automatically. Now
navigate to the desired directory and use Rosie as usual.  


