Some of the libraries in this directories have been copied from other projects.
We should find a proper way to import them to avoid having to keep those in
synchrony.

  - There used to be a `utils` directory, this have been moved into
    [toclbox](https://github.com/efrecon/toclbox) a separate module that also is
    declared as a git submodule. `toclbox` contains a `utils` package that is
    backwards compatible with what used to be in the `utils` directory.
  - `templater` also comes from [biot](https://bitbucket.org/enbygg3/biot/).
    There are other similar Tcl [implementations](http://wiki.tcl.tk/18175)
    around, we might want to look into them at some point.
  - `docker` is a copy of the main library from the
    [Docker client](https://github.com/efrecon/docker-client) implementation
    in Tcl.