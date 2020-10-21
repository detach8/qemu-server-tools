#!/usr/bin/perl
#
# QEMU Server Control Tool (version 0.2a)
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
use Cwd;
use Fcntl;
use Fcntl ':flock';
use POSIX qw(setsid mkfifo);
use POSIX ':sys_wait_h';

# program version information
my $APPNAME = "QEMU Server Control Tool";
my $VERSION = "0.2a";
my $COPYRIGHT = "Copyright (C) 2006, Securlogic Singapore Pte Ltd";

# set to 1 to enable debugging output
my $DEBUG = 0;

# qemu-server running directory
my $STATUSDIR = "/var/run/qemu/";

# number of VNC displays to make available
my $VNCDISPLAYS = 100;

# priority to use for qemu
my $PRIORITY = -5;

# default files to use in vmdir
my $CONFFILE	= "qemu.conf";
my $PIDFILE	= "qemu.pid";
my $VNCFILE	= "qemu.vnc";
my $LOGFILE	= "qemu.log";
my $PIPEFILE	= "qemu.pipe";
my $VMSTATE	= "qemu.state";

# get available vnc displays
# note: this line must come after all the files has been declared
my %STATUS = getstatus();
my $VNC = getvnc(%STATUS);

# default config options
my @CONFIG = (
	"pidfile=$PIDFILE",
	"vnc=$VNC",
	"monitor=stdio",
	"localtime",
	"usbdevice=tablet");

# illegal config options to skip
my %ILLEGAL = ('pidfile', 'vnc', 'monitor');

### begin ###

if ($#ARGV < 0 || $ARGV[0] eq "--help") { usage(); }
elsif ($ARGV[0] eq "list") 	{ list(); }
elsif ($ARGV[0] eq "start")	{ start(); }
elsif ($ARGV[0] eq "stop")	{ writepipe($ARGV[1], "quit", 1); }
elsif ($ARGV[0] eq "pause")	{ writepipe($ARGV[1], "stop", 1); }
elsif ($ARGV[0] eq "resume")	{ writepipe($ARGV[1], "cont", 1); }
elsif ($ARGV[0] eq "reset")	{ writepipe($ARGV[1], "system_reset", 1); }
elsif ($ARGV[0] eq "suspend")	{ suspend(); }
elsif ($ARGV[0] eq "restore")	{ restore(); }
elsif ($ARGV[0] eq "commit")	{ writepipe($ARGV[1], "commit", 1); }
elsif ($ARGV[0] eq "exec")	{ writepipe($ARGV[1], $ARGV[2], 1); }
else { printerror("Unknown command \"$ARGV[0]\". See qemu-server --help."); }

sub printdebug($)
{
	my $msg = shift;
	print STDERR "(DEBUG) $msg\n" if ($DEBUG);
}

sub printerror($)
{
	my $msg = shift;
	print STDERR "(ERROR) $msg\n";
	exit(-1);
}

sub printwarn($)
{
	my $msg = shift;
	print STDERR "(WARN) $msg\n";
}

sub printmsg($)
{
	my $msg = shift;
	print STDOUT "$msg\n";
}

sub checkvmdir($)
{
	my $vmdir = shift;

	printerror("vmdir $vmdir is not an absolute pathname") unless ($vmdir =~ m/^\//);
	printerror("vmdir $vmdir is not a directory") unless (-d $vmdir);
	printerror("vmdir $vmdir is not readable") unless (-r $vmdir);

	# append trailing slash
	$vmdir = "$vmdir/" if (!$vmdir =~ m/\/$/);

	return $vmdir;
}

sub getstatus()
{
	my %status;
	my $dir = cwd();

	if (! -d $STATUSDIR)
	{
		printdebug("Creating status directory $STATUSDIR");
		mkdir($STATUSDIR, 0700);
	}

	printdebug("Reading files in $STATUSDIR");
	opendir(DIR, $STATUSDIR) or printerror("Can't open status dir $STATUSDIR");

	foreach (readdir(DIR))
	{
		chomp;

		chdir($STATUSDIR) or printerror("Can't chdir to $STATUSDIR");

		printdebug("Checking status file $_");
		if (!m/\./ && -f $_ && -r $_)
		{
			printdebug("Reading status file $_");
			open(FH, $_) or printerror("Can't open status file $_");
			my $vmdir = <FH>;
			chomp($vmdir);
			close(FH);

			chdir($vmdir) or printerror("Can't chdir to $vmdir");

			printdebug("\t$vmdir");

			if (-r $VNCFILE && -r $PIDFILE)
			{
				open(VNC, $VNCFILE);
				$status{$vmdir}{'vnc'} = <VNC>;
				chomp $status{$vmdir}{'vnc'};
				close(VNC);

				printdebug("\t\tvnc=$status{$vmdir}{'vnc'}");

				open(PID, $PIDFILE);
				$status{$vmdir}{'pid'} = <PID>;
				chomp $status{$vmdir}{'pid'};
				close(PID);

				printdebug("\t\tpid=$status{$vmdir}{'pid'}");
			}
		}

	}

	closedir(DIR);

	chdir($dir) or printerror("Can't chdir to $dir");

	return %status;
}

sub addstatus($)
{
	my $vmdir = shift;
	my $dir = cwd();

	chdir($STATUSDIR) or printerror("Can't chdir to $STATUSDIR");

	printdebug("Writing status file $$");
	open(FH, ">", $$) or printerror("Can't open status file $$ for writing");
	flock(FH, LOCK_EX) or printwarn("Can't get exclusive lock on status file $$");
	print FH ($vmdir);
	flock(FH, LOCK_UN);
	close(FH);

	chdir($dir) or printerror("Can't chdir to $dir");
}

sub delstatus()
{
	my $dir = cwd();

	chdir($STATUSDIR) or printerror("Can't chdir to $STATUSDIR");

	printdebug("Unlinking status file $$");
	unlink($$) or printerror("Can't unlink status file $$");

	chdir($dir) or printerror("Can't chdir to $dir");
}

sub getvnc()
{
	my @displays;
	my $ref = shift;

	printdebug("Finding next available VNC display...");

	# create displays to use
	for (my $i = 0; $i < $VNCDISPLAYS; $i++) { $displays[$i] = 0; }

	foreach (keys(%STATUS))
	{
		printdebug("\t$_ is already using display $STATUS{$_}{'vnc'}");
		$displays[$STATUS{$_}{'vnc'}] = 1;
	}

	for (my $i = 0; $i < $VNCDISPLAYS; $i++)
	{
		if ($displays[$i] == 0)
		{
			printdebug("Found available display at :$i");
			return $i;
		}
	}

	printerror("No available VNC displays found");
}

sub readconfig($)
{
	my $vmdir = shift;
	my $dir = cwd();
	my @config = @CONFIG;

	chdir($vmdir) or printerror("Can't chdir to $vmdir");

	if (-f $CONFFILE)
	{
		printdebug("Reading config file $CONFFILE");
		open(FH, $CONFFILE) or printerror("Can't read config file $CONFFILE");

		while (<FH>)
		{
			chomp;

			if (!m/^#+|^$/)
			{
				my ($key, $val) = split(/=/, $_, 2);

				if (exists($ILLEGAL{$key}))
				{
					printwarn("Illegal config \"$_\" found in config file, skipping");
				}
				else
				{
					push(@config, $_);
				}
			}
		}

		close(FH);
	}
 	else
	{
		printerror("Can't find config file $CONFFILE");
	}

	chdir($dir) or printerror("Can't chdir to $dir");

	return @config;
}

sub buildopts(@)
{
	my @config = @_;
	my @opts;

	printdebug("Building command line options...");

	# build provided configs
	foreach (@config)
	{
		my ($key, $val) = split(/=/, $_, 2);

		printdebug("\t-$key");
		push(@opts, "-$key");

		if ($val ne "")
		{
			printdebug("\t$val");
			push(@opts, $val);
		}
	}

	return @opts;
}

sub cleanup($)
{
	my $vmdir = shift;
	my $dir = cwd();

	printdebug("Cleaning up $vmdir");
	chdir($vmdir) or printerror("Can't chdir to $vmdir");

	printdebug("\t$VNCFILE");
	unlink($VNCFILE) or printwarn("Can't unlink $VNCFILE");

	printdebug("\t$PIPEFILE");
	unlink($PIPEFILE) or printwarn("Can't unlink $PIPEFILE");

	printdebug("\t$PIDFILE");
	unlink($PIDFILE) or printdebug("Can't unlink $PIDFILE (this is normal)");

	chdir($dir) or printerror("Can't chdir to $dir");
}

sub writepipe($$;$)
{
	my $vmdir = checkvmdir(shift());
	my $cmd = shift();
	my $output = shift();

	chdir($vmdir) or printerror("Can't chdir to $vmdir");

	if (-p $PIPEFILE)
	{
		printdebug("Forking process");
		my $pid = fork();

		# child
		if ($pid == 0)
		{
			printmsg("Executing command \"$cmd\", see $LOGFILE in $ARGV[1] for output.") if ($output);

		printdebug("Sending command \"$cmd\" using $PIPEFILE");
				open(FH, ">", $PIPEFILE) or printerror("Can't open named pipe $PIPEFILE for writing");
			flock(FH, LOCK_EX);
			print FH ("$cmd\n");
			flock(FH, LOCK_UN);
			close(FH);

			exit(0);
		}

		# parent
		else
		{
			my $count = 0;

			do
			{
				if ($count > 3)
				{
					printwarn("Error executing command \"$cmd\" - no response from QEMU.") if ($output);
					printdebug("Killing child pid $pid");
					my $ret = kill(9, $pid);
					printdebug("kill(9, $pid), returned $ret");
				}

				sleep(1);
				$count++;
			}
			until (waitpid($pid, WNOHANG) > 0)
		}
	}
	else
	{
		printerror("Can't find named pipe $PIPEFILE in $vmdir - is the VM running?");
	}
}

sub start()
{
	my $vmdir = checkvmdir($ARGV[1]);

	if (exists($STATUS{$vmdir}))
	{
		printerror("Another copy of VM is already running in $vmdir");
	}

	printmsg("Assigned VNC display :$VNC to $vmdir");

	printdebug("Forking process");
	my $pid = fork();

	# child
	if ($pid == 0)
	{
		setsid();

		chdir($vmdir) or printerror("Can't chdir to $vmdir");

		my @config = readconfig($vmdir);
		my @opts = buildopts(@config);

		if (! -e $PIPEFILE)
		{
			printdebug("Creating named pipe $PIPEFILE");
			mkfifo($PIPEFILE, 0600) or printerror("Can't create named pipe $PIPEFILE");
		}

		# write VNC display to $VNCFILE
		printdebug("Creating vnc file $VNCFILE");
		open(FH, ">", $VNCFILE) or printerror("Can't write VNC display file $VNCFILE");
		flock(FH, LOCK_EX);
		print FH ($VNC);
		flock(FH, LOCK_UN);
		close(FH);

		addstatus($vmdir);

		printdebug("Trying to load KQEMU kernel module...");
		system("modprobe", "kqemu", "major=0") == 0
			or printwarn("Can't load KQEMU kernel module");

		printdebug("Redirecting STDOUT to $LOGFILE");
		open(STDOUT, ">>", $LOGFILE) or printerror("Can't redirect STDOUT to $LOGFILE");

		printdebug("Redirecting $PIPEFILE to STDIN");
		sysopen(STDIN, $PIPEFILE, O_RDONLY | O_NONBLOCK) or printerror("Can't redirect $PIPEFILE to STDIN");

		printdebug("Changing process priority to -10");
		system("renice", $PRIORITY, "-g", getpgrp()) == 0
			or printwarn("Can't renice PID $pid");

		printdebug("Starting QEMU in background...");
		system("qemu", @opts) == 0
			or printwarn("QEMU exited abnormally");

		printdebug("Closing STDIN and STDOUT");
		close(STDIN);
		close(STDOUT);

		delstatus();

		cleanup($vmdir);

		exit(0);
	}
}

sub list()
{
	my $count = 0;
	my $template = "A38A6A6";

	# print some headers
	printmsg("");
	printmsg("$APPNAME (version $VERSION)");
	printmsg("$COPYRIGHT");
	printmsg("");
	printmsg(pack($template, "vmdir", "vnc", "pid"));

	# draw horizontal dashed line
	for (my $i = 0; $i < 50; $i++) { print("-"); }
	printmsg("");

	# loop thru status
	foreach (keys(%STATUS))
	{
		printmsg(pack($template, $_, $STATUS{$_}{'vnc'}, $STATUS{$_}{'pid'}));
		$count++;
	}

	printmsg("");
	printmsg("Total running VMs: $count");
}

sub suspend()
{
	writepipe($ARGV[1], "savevm $VMSTATE", 0);
	sleep(1);
	writepipe($ARGV[1], "quit", 0);
	printmsg("Suspended VM to file $VMSTATE");
}

sub restore()
{
	if (-r "$ARGV[1]/$VMSTATE")
	{
		start();
		sleep(1);
		writepipe($ARGV[1], "loadvm $VMSTATE");
		printmsg("Restored VM from file $VMSTATE");
	}
	else
	{
		printerror("Can't find/read VM state file $VMSTATE in $ARGV[1]");
	}
}

sub usage()
{
print <<EOF;

$APPNAME (version $VERSION)
$COPYRIGHT

Usage: qemu-server command [parameters]

Command     Parameters         Description
list                           List all running VMs
start       [vmdir]            Start a VM
stop        [vmdir]            Shutdown a VM
reset       [vmdir]            Reset a VM
pause       [vmdir]            Pause a VM
resume      [vmdir]            Resume a paused VM
suspend     [vmdir]            Suspend a VM
restore     [vmdir]            Restore a suspended VM
commit      [vmdir]            Commit disk data (snapshot mode)
exec        [vmdir] [cmd]      Execute a QEMU monitor command

Note:
  vmdir must be an absolute pathname, e.g. /vm/testvm1

Examples:
  qemu-server list
  qemu-server start /vm/testvm1/
  qemu-server exec /vm/testvm1/ "info kqemu"

EOF

exit(-1);
}
