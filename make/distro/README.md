# Platform binaries

This directory will contain the platform binaries that are made using
`make.tcl`. These are "cross-compiled", meaning that binaries for, e.g. Windows,
can be created on a linux machine. In practice, this means arranging for putting
all the relevant tcl dependencies (scripts) within a self-contained binary for
each platform.