prefix=${HOME}/local/bin

all:
	@echo 'Run make install prefix=/path/to/install'
	@echo 'default prefix is ${prefix}'

install:
	cp git-* ${prefix} 

