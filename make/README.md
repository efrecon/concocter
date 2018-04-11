# Making Binary Releases

This sub-folder contains all the tools to make binary releases of concocter.
This provides a rather hacky, but working and generic framework for the creation
of self-contained tcl-based binaries. These binaries can simply be copied onto a
host and run, provided access to system base libraries (glibc on linux, etc.).

## Making a Release

The make "system" automatically ask `concocter` for its release number, so
making a release should more or less be done according to the following steps:

* Increase of change the version number of `concocter` directly in the script
  implementation.
* From within this very directory, run `make.tcl`. This will create binaries for
  **all** the supported platforms in the [distro](distro/) sub-folder. These binaries
  will be automatically tagged with the name of the platform and the version
  number.
* Tag the version using git, using the same version as the version number.
* Make an official release using that tag at github, and pushing the binaries as
  part of the release.

Note that binaries generated in `distro/` are automatically been placed out of
version control using a `.gitignore` directive. Note also that this procedure
has only been tested on linux.

### Design Principles

The make system uses a [contract](bin/bootstrap.dwl) to describe the origin of
the various tclkits that will be used for the creation of the self-contained
binaries. These binaries will be placed under directories named after the name
of the platform under the [bin](bin/) directory. A specific `.gitignore`
directive ensures that these binaries are also kept outside of version control.
This is because most of them originate from a generic
[repository](https://github.com/efrecon/tclkit) also under our control.

In a similar vein, a working version of [sdx](https://wiki.tcl.tk/3411) is
automatically downloaded and installed under [kits](kits/) if necessary, and
placed outside version control.

When making self-contained binaries, `sdx` will be run against a temporary
wrapping directory.

### Options

`make.tcl` provides a number of options to control its behaviour. Options are
led by a single dash and can be shortened to their minimal common denominator.
These options are:

* `-targets` takes the list of target to make. It defaults to the only target
  that is known to the make system, i.e. `concocter`.
* `-version` forces to make binaries of a specific version number. When not
  present, the make system will request `concocter` for its version number. This
  can be used for generating beta version to friends.
* `-force` will force the (re)downloading of the various binary files even if
  they are already present on disk. This can be used to adapt to newer versions
  of Tcl, for example.
* `-keep` will not remove the content of the wrapper temporary directory. This
  can be used for debugging the internals of the make system.
* `-platforms` will list the platforms that are supported and exits. This is
  directed by the content of the download contract described above.
* `-wrapper` is the directory in which to create the wrapping directory. This
  defaults to the current directory, but could also be `/usr/tmp/` or similar.
  Current directory is used to avoid "complex" multi-platform behaviour not
  necessary for the task of making binaries from time to time.
* `-verbosity` is the verbosity level of the output. It takes something accepted
  by
  [toclbox](https://github.com/efrecon/toclbox/blob/master/toclbox/log-1.0.tm)

## Directory Organisation

Most directories are automatically filled by `make.tcl` at one point in time.
These are as follows:

* `bin/` will contain tclkit binaries for the generation of self-contained
  binaries for the various supported platforms. See above for more details.
* `distro/` will contain the self-contained binaries that are generated.
* `kits/` will contain utility kits necessary for wrapping binaries, etc.
* `lib/` offloads part of the implementation of the main script to a "module" to
  reduce the complexity of the main script. This is a rather ugly hack as, for
  example, some global variables are shared and even modified by these
  procedures.
