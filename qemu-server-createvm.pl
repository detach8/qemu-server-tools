#!/usr/bin/perl
#
# QEMU Server VM Creation Tool (version 0.1a)
#
# Copyright (C) 2006, Securlogic Singapore Pte Ltd
#
# Author: Justin Lee <justin.lee@securlogic.com>
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation; either version 2 of the License, or (at your option) any later
# version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
# details.
#
# You should have received a copy of the GNU General Public License along with
# this program; if not, write to the Free Software Foundation, Inc., 51
# Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
#

use strict;

my $APPNAME = "QEMU Server VM Creation Tool";
my $VERSION = "0.1a";
my $COPYRIGHT = "Copyright (C) 2006, Securlogic Singapore Pte Ltd";

my $DISKFILE = "disk1.raw";
my $CONFFILE = "qemu.conf";
my @CONFDATA = (
	"hda=$DISKFILE",
	"cdrom=/dev/cdrom",
	"boot=d",
	"net=nic",
	"net=tap",
	"kernel-kqemu"
);

sub printerror($)
{
	my $msg = shift;
	print STDERR ("(ERROR) $msg\n");
	exit(-1);
}

if ($#ARGV < 1) { usage(); }
else
{
	print("$APPNAME (version $VERSION)\n");

	if (-d $ARGV[0]) { printerror("Directory $ARGV[0] already exists!"); }

	print("Creating directory $ARGV[0]... ");
	mkdir($ARGV[0]) or printerror("Can't create directory $ARGV[0]");
	print("done\n");

	chdir($ARGV[0]) or printerror("Can't cwd to directory $ARGV[0]");

	print("Creating disk image $DISKFILE...\n");
	system("qemu-img", "create", "-f", "raw", $DISKFILE, $ARGV[1]) == 0
		or printerror("Can't run qemu-img to create disk image (check \$PATH)");

	print("Wiriting config file $CONFFILE... ");
	open(FH, ">", $CONFFILE);
	foreach (@CONFDATA) { print FH ("$_\n"); }
	close(FH);
	print("done\n");

	print("Run \"qemu-server start $ARGV[0]\" to start VM.\n");
}

sub usage()
{
print <<EOF

$APPNAME (version $VERSION)
$COPYRIGHT

Usage: qemu-server-createvm [vmdir] [size]

Creates a VM in directory [vmdir] of size [size]
See qemu-img on the usage of [size]

Example:
  qemu-server-createvm /vm/myvm1/ 5G

EOF
}
