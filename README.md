# Concocter

The main goal of `concocter` is to generate all the necessary configuration files
based on the content of remote locations before starting another program. In
order to generate the configuration files, `concocter` supports a flexible
templating system based on the Tcl-language. The content of (remote) resources
is represented as variables, and these variables can be used as part of the
configuration files. In addition, `concocter` has support for `docker`: it will
be able to generate configuration files using the current dynamic state of the
docker daemon through exposing a wide number of properties for each running
container, including their environment variables.

In its most simple form, `concocter` will get the content of all specified
variables, generates configuration files using the templates and the content of
the variables and replaced itself with the program under its control. But
`concocter` is also able to regularily update the content of all variables,
regenerate configuration files whenever content has changed and (re)start the
program under its control as necessary. Instead of pure restarting, `concocter`
is able to send `HUP`, `USR1` or similar signals to the program to notify it
about configuration changes, if possible.

## Variables

`concocter` supports four different types of variables:

  - Variables which specification starts with a `@` are understood as the
    content of a (possibly) remote resource. All characters that follow the `@`
    sign should be an URL and `concocter` will get the content from that URL and
    assign it to the variable internally. `concoter` only recognises HTTP/S and
    a special docker construct (see below) at present and considers any other
    URL as being a ... local file.

  - Variables which specification starts with a `=` are understood as a proper
    Tcl mathematical [expression](https://www.tcl.tk/man/tcl/TclCmd/expr.htm).
    Within that expression, any string surrounded by `%` is considered the name
    of a variable and the whole string will be replaced by the content of that
    variable before the expression is evaluated.
    
  - Variables which specification starts with a `^` are understood as the
    gathering of file statistics for the path formed by the remaining of the
    specification. The variable will be a Tcl array reflecting the regular
    calling of `file stat` on the path. Whenever the path is a directory, the
    array will also contain an index called `files` that will contain the list
    of files directly in the directory (no-recursion).

  - Variables which specification starts with a `!` are understood as an
    external process to execute. The result of the process will be set to the
    content of the variable. At present, there is no protection whatsoever
    against malicious usage, so you should use this facility with caution. 

  - Otherwise, the specification will be the content of the variable. Within
    that specification, any string surrounded by `%` is considered the name of a
    variable and it will be replaced by the content of that variable before the
    expression is evaluated. In addition to internal variables, `concocter` is
    also able to pick up the content of environment variables and to default to
    a value whenever a variable does not exist. The default value is then
    separated from the name of the variable using a `|` sign.

Variables are specified through the option `-vars`. While it is possible to
directly specify a tcl-compliant list as a value, in most cases, you will want
to lead the value of the `-var` option with a `@` sign. This is understood as a
file indirection by `concocter`, meaning that the specifications of these
variables is read from the file instead. In the path, `%`-surrounded
strings will automatically be replaced by their value. Recognised are all
environment variables and all the keys of the internal
[platform](https://www.tcl.tk/man/tcl/TclCmd/tclvars.htm).

Within the file blank lines are ignored, as well as lines starting with `#`.
Otherwise, each line should be a valid Tcl list where the first argument is the
name of the variable, the second is the specification for the source of that
variable (remote location or mathematical expression) and the last (optional)
argument is the default value for the variable. The following is an example:

```
# Declare a variable to contain the whole content of the main github page
github @https://github.com/
# Declare two variables, one depending on the content of the first one
a 10
b =%a%+67
```


## Outputs

Outputs are composed of a file location, i.e. where to put the configuration
file on disk, and of the location of a template or the content of a template.
This template will be used to generate the content of that configuration file
based on the variables declared as described in the previous section. Outputs
are specified through the option `-outputs`, this option operates similarily to
the `-vars` option with respect to the leading `@` in its value. To specify a
template file, you should lead its path with the `@`-sign.

In both the path to the configuration file to generate and to the template, `%`
surrounded strings will be replaced by their values. Recognised are all
environments variables and content of the `platform` specification, as for the
variables. But also recognised are the names of all the variables and the three
additional: `dirname`, `fname` and `rootname` which refer to the directory,
filename and filename without extension of the file where from the outputs
specification was read.

All text within the template will be output to the configuration file, unless
sections of the files surrounded by `<%` (opening) and `%>` (closing). Within
these opening and closing marker, any tcl code can be executed. All variables
specified via the `-vars` option are made available as regular Tcl variables.
The specific leading `<%=` can be used to output the content of the enclosed Tcl
expression. Execution of the code is done in a
[safe](https://www.tcl.tk/man/tcl/TclCmd/safe.htm) interpreter to prevent access
to any local (host) resources. Calling the command `source` is allowed, but file
paths will be jailed to the directory location of the sourcing template,
whenever this is available.

The following example would arrange for the content of the github main page
acquired as part of the previous example to be dumped to the local disk (this is
a contrieved example!). It dumps the content of the `github` variable using the
expression output led by `<%=`. Of course, it would be possible to transform
this HTML in any possible way, but you would probably reference to a template
path and lead that reference with an `@`-sign.

```
# Dump to the github.htm file in the same directory as where we were read from
%dirname%/github.htm "<%=$github%>"
```


## Interaction with the external program

The path to the program placed under our control and all its arguments is
considered to be anything that follows the double dash `--` at the command-line.
When `-update` is positive, it should specify the number of seconds at which to
check (and update) the values of the variables. Whenever any variable changes,
all templated outputs will be regenerated and the program will be sent a series
of signal in sequence, as specified using the `-kill` option. The value of this
option should be an even list where the first argument is the name/number of the
signal and the second argument the number of milliseconds to wait before sending
the next signal or taking decision. `concocter` recognises "killing" signals and
is able to detect the disappearing of the process under its control so as to
restart it. However, it is possible to use the `-kill` option to send more
gentle signals so as to tell the program under control to reload its
configuration from files that we would have just re-generated.


## Forcing Template (re)generation

`concocter` supports an external command through the `-external` command-line
option. When an external command is set, the command will be called at each
regular polling of the variables and its result can influence `concocter` so
that it (re)generates the templates (and possibly restart the program under its
control). There are three types of external command recognised by `concocter`:

* The path to a script, when the extension of the first item is `.tcl`. In that
  case, the script will be loaded into a separate interpreter with full power.
  The path to the script will become `argv0` in the script and the remaining
  arguments will be reflected by `argv`. When the script returns a non-zero
  value, `concocter` will regenerate the templates.
  
* A path, similar to the above case, containing an `@` sign (arobas). In that
  case, what precedes the sign is considered to be the name of a procedure to be
  called each time `concocter` wants to poll for template regeneration. As
  opposed to the case above, the interpreter is kept between checks, meaning
  that it will be possible to save state between runs as part of the variables
  of the interpreter. `argv0` and `argv` are otherwise treated as above. When
  the procedure call contains `!` signs, these are considered to be separating
  arguments that will be passed to the procedure (which then is the first
  argument of the `!` separated string). When the procedure returns a non-zero
  value, `concocter` will regenerate the templates.
  
* Anything else is considered a command that `concocter` will run to decide for
  template regeneration. Whenever its exit code is non-zero, `concocter` will
  regenerate the templates.


## Docker Support

`concocter` is able to communicate with a running docker daemon and
automatically creates variables to reflect the current status of all running
containers known at the daemon. Docker support is triggered whenever a variable
of any name is associated to a source which specification is similar to
`@docker+unix:///var/run/docker.sock`. Anything that follows the `+` in that URL
is considered the location of the docker daemon.

The name of the variable is used as the base for a number of other
auto-generated variables. The variable itself will contain the list of (short)
containers identifiers running at the daemon. For each container, a series of
variables starting with the name of the main variable, followed by a dash and
followed by the identifier of the container will be created. So, for example, if
the variable was named `docker`, and if only one container with short identifier
`7161b422b031` was running, a series of variables which name starts with
`docker-7161b422b031` would be created by appending using the following suffixes
to this core name:

  - `-id` will contain the full identifier of the container.
  - `-name` will contain the name of the container.
  - `-ip` will contain the IP address of the container on the bridge network.
  - `-mac` will contain the MAC address of the container on the bridge network.
  - `-ports` will contain the list of external ports actually forwarded. Each
    port specification will be composed of the port number, followed by a slash,
    followed by the type, e.g. `tcp`.
  - `-image` will contain the name of the image that led to the container.
  - `-environment` will contain the list of environment variables that are
    present within the container.
  - For each environment variable, a dash, the keyword `environment`, another
    dash and the name of the environment variable will also lead to a new
    variable.
  - `-label` will contain the list of labels that are associated to the
    container.
  - For each label, a dash, the keyword `label`, another dash and the name of
    the label will also lead to a new variable.


## Implementation Notes

The different variable types that are recognised by `concocter` are driven by a
set of plugins to maximise flexibility. The matching between the variable
specifications and the plugins to use is driven by the file called `plugins.spc`
in the main implementation of the library.


## Test and Example

The sub-directory `test` contains a number of files that can be used to exercise
and understand the inner workings of `concocter` without any external
dependencies. The test uses many of the sugaring facilities that are offered by
`concoter` to exhibit their usefullness and provide a hands-on example. From the
main directory, start the test using the following command:

```
./concocter.tcl -vars @%progdir%/test/vars.cfg -outputs @%progdir%/test/dst.cfg -update 10 -verbose "templater 3 utils 2 * 6" -- ./test/slowprinter.tcl ./test/concocter.tcl
```

The test arranges to declare a variable that points at the content of the
`concocter` main script and places a mirror and reversed copy of the main script
under the same name, but in the `test` sub-directory. This is achieved through
calling a procedure that is sourced from an external file to exercise this
particular facility. `slowprinter.tcl` slowly prints out the content of the
template-generated copy of the main script on the standard output. As the
command increases logging, you should be able to witness whenever
`concocter` tries to update the content of its variables at a regular pace (but
does not succeeds in doing so since the content does not change between checks).

If you add the option `-external reload@%prgdir%/test/hook.tcl` to the command
above, you should be able to see that the `reload` command decides on a random
basis to regenerate the templates and restart the reverse output program.