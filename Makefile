all: qemu-server qemu-server-createvm

qemu-server: qemu-server.pl
	perlcc -B -o qemu-server qemu-server.pl

qemu-server-createvm: qemu-server-createvm.pl
	perlcc -B -o qemu-server-createvm qemu-server-createvm.pl

clean:
	rm -fv qemu-server qemu-server-createvm

uninstall: /usr/local/bin/qemu-server /usr/local/bin/qemu-server-createvm
	rm -fv /usr/local/bin/qemu-server
	rm -fv /usr/local/bin/qemu-server-createvm
	rm -fv /etc/qemu-ifup

install: qemu-server qemu-server-createvm qemu-ifup
	install -m 755 qemu-server /usr/local/bin
	install -m 755 qemu-server-createvm /usr/local/bin
	install -m 755 qemu-ifup /etc

reinstall: uninstall clean install
