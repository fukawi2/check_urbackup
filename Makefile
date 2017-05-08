D_BIN=/usr/local/bin

all: install

install: test
	# install the actual scripts
	install -D -m 0755 src/check_urbackup.sh $(DESTDIR)$(D_BIN)/check_urbackup

test:
	bash -n src/check_urbackup.sh
