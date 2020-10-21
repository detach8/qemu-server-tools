
# QEMU Server Tools

QEMU Server Tools is a set of simple command-line scripts written in
Perl to manage multiple QEMU VMs easily without requiring a graphical
frontend.

It organizes VMs into directories and mimics the usage of command line
tools from VMware Server.

## Requirements

QEMU Server requires the following components to be installed:

* **QEMU 0.8.1** or newer (with VNC support)
* **Perl 5.8.x** or newer

In addition, the following optional components are recommended:

* **KQEMU 1.3.0pre9** or newer
* **Linux `bridge-utils`** installed and configured and the
  [qemu-ifup](qemu-ifup) script placed in /etc

## Installation / Uninstallation

QEMU Server will automatically install itself to `/usr/local/bin`.
If you do not wish to use this directory, edit `Makefile`.

To download:

    git clone https://github.com/detach8/qemu-server.git

To install:

    make
    make install

To uninstall:

    make uninstall

_Note: Make sure your perl executables are installed in a location
defined in the system path $PATH (usually `/usr/local/bin`) before
running `make`, otherwise it will fail._

## Usage

### VM Management (qemu-server)

This tool allows you to manage QEMU VMs easily. Its full set of arguments
are shown when running the command without any arguments.

    qemu-server

To start a VM in `/vm/myvm1`:

    qemu-server start /vm/myvm1

To stop a VM in `/vm/myvm1`:

    qemu-server stop /vm/myvm1

To show a list of running VMs:

    qemu-server list

### VM Creation (qemu-server-createvm)

This tool helps you create a VM quickly. It creates a directory with two
files `disk1.raw` and `qemu.conf`. It uses `qemu-img` to create the disk
image file and adds some default configuration to `qemu.conf` as well.

The following example creates a VM in `/vm/myvm1` with a 2G disk:

    qemu-server-createvm /vm/myvm1 2G

_Note: Make sure the `qemu-img` binary is installed in a location defined
in the system path $PATH (usually `/usr/local/bin`). Otherwise, this tool
will fail to work._

## VM Directory (vmdir)

QEMU Server will create/use the following files in a VM directory:

| File        | Purpose                                                  |
| ----------- | -------------------------------------------------------- |
| qemu.conf   | Configuration information _(mandatory)_                  |
| *.raw       | Disk image file, specified in qemu.conf _(mandatory)_    |
| qemu.pid    | Contains PID of running copy of QEMU                     |
| qemu.pipe   | Named pipe for sending commands to QEMU monitor          |
| qemu.log    | Output from QEMU monitor                                 |
| qemu.state  | VM state file _(created when VM is suspended)_           |

## VM Configuration File (qemu.conf)

The VM configuration file `qemu.conf` stores a list of options to pass
to `qemu` via the command line. Each line represents a single qemu
option, for example:

    # This is a comment
    hda=disk1.raw
    cdrom=mydisc.iso
    kernel-kqemu

Will translate to:

    qemu -hda disk1.raw -cdrom mydisc.iso -kernel-kqemu

### Mandatory Configuration Lines

The VM configuration file _must_ contain the following mandatory lines in
order to operate properly:

    # Primary hard disk image file
    hda=<file>

### Illegal Configuration Lines

The VM configuration file should _not_ contain the following lines as they
are automatically added by QEMU Server:

    pidfile=<file>
    vnc=<display>
    monitor=<char device>

Adding the above lines to the configuration file will cause `qemu-server`
to generate a warning message during startup.

## Contributing

Pull requests are welcome. For major changes, please open an issue first to discuss what you would like to change.

## Maintainers

This project has been moved from the original web site at SourceForge
and is no longer under active development.

* Justin Lee (2006) - https://github.com/detach8

## License

This project is licensed under the [GNU General Public License v2](LICENSE).
