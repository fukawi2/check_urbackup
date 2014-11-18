D_BIN=/usr/local/bin

all: install

install:
	# install the actual scripts
	install -D -m 0755 src/check_urbackup.sh $(DESTDIR)$(D_BIN)/check_urbackup
