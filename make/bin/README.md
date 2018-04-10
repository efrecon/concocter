# Tclkit Binaries

This directory contains binaries for a various number of tclkit, i.e.
single-contained Tcl interpreters, bundled with a number of libraries and
packages. These binaries will be used for making the final concocter binaries.

There should be one sub-directory per platform that is supported. While the main
objective was to provide support for downloading the binaries (thus not making
them part of the git repo), this is not possible at present as there do not seem
to be tclkits that are built with TLS built in. Instead all binaries have been
built online using the [kitcreator](http://kitcreator.rkeene.org/kitcreator) and
with the following options:

* Creator version: 0.10.2
* Tcl version: 8.6.8
* Static binaries
* Packages: Metakit, Tcllib, TLS
* Minimal build

We should really get rid of Tcllib, which should minimise the size of the
binaries. However, it seems that concocter depends on a number of packages when
running the RESTish interface. Stricter selection of required packages, through
enabling the tcllib downloading code and only copying necessary packages would
allow to minimise the size of the binary further.