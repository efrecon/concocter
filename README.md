# Concocter

The main goal of `concocter` is to generate all the necessary configuration files
based on the content of remote locations before starting another program. In
order to generate the configuration files, `concocter` supports a flexible
templating system based on the Tcl-language. The content of (remote) resources
is represented as variables, and these variables can be used as part of the
configuration files.

In its most simple form, `concocter` will get the content of all specified
variables, generates configuration files using the templates and the content of
the variables and replaced itself with the program under its control. But
`concocter` is also able to regularily update the content of all variables,
regenerate configuration files whenever content has changed and (re)start the
program under its control as necessary. Instead of pure restarting, `concocter`
is able to send `HUP`, `USR1` or similar signals to the program to notify it
about configuration changes, if possible.

## Variables

`concocter` supports three different types of variables:

  - Variables which specification starts with a `@` are understood as the
    content of a (possibly) remote resource. All characters that follow the `@`
    sign should be an URL and `concocter` will get the content from that URL and
    assign it to the variable internally. `concoter` only recognises HTTP/S at
    present and considers any other URL as being a ... local file.

  - Variables which specification starts with a `=` are understood as a proper
    Tcl mathematical [expression](https://www.tcl.tk/man/tcl/TclCmd/expr.htm).
    Within that expression, any string surrounded by `%` is considered the name
    of a variable and the whole string will be replaced by the content of that
    variable before the expression is evaluated.

  - Otherwise, the specification will be the content of the variable. Within
    that specification, any string surrounded by `%` is considered the name of a
    variable and it will be replaced by the content of that variable before the
    expression is evaluated.

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
b %a%+67
```

## Outputs

Outputs are composed of a file location, i.e. where to put the configuration
file on disk, and of the location of a template to generate the content of that
configuration file based on the variables declared as described in the previous
section. Outputs are specified through the option `-outputs`, this option
operates similarily to the `-vars` option with respect to the leading `@` in its
value.

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
to any local (host) resources.

The following example would arrange for the content of the github main page
acquired as part of the previous example to be dumped to the local disk (this is
a contrieved example!).

```
# Dump to the github.htm file in the same directory as where we were read from,
# using the template specified from `inline.tpl` in that same directory
%dirname%/github.htm %dirname%/inline.tpl
```

This example would only require `inline.tpl` to contain the following line,
which dumps the content of the `github` variable using the expression output led by
`<%=`. Of course, it would be possible to transform this HTML or to add
surrounding tags, for example.

```
<%=$github%>
```

## Interaction with the external program

The path to the program placed under our control and all its arguments is
considered to be anything that follows the double dash `--` at the command-line.
When `-update` is positive, it should specify the number of seconds at which to
check (and update) the values of the variables. Whenever, any variable changes,
all templated outputs will be regenerated and the program will be sent a series
of signal in sequence, as specified using the `-kill` option. The value of this
option should be an even list where the first argument is the name/number of the
signal and the second argument the number of milliseconds to wait before sending
the next signal or taking decision. `concocter` recognises "killing" signals and
is able to detect the disappearing of the process under its control so as to
restart it. However, it is possible to use the `-kill` option to send more
gentle signals so as to tell the program under control to reload its
configuration from files that we would have just re-generated.

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
`concocter` main script and places a copy of the main script under the same
name, but in the `test` sub-directory. `slowprinter.tcl` slowly prints out the
content of the template-generated copy of the main script on the standard
output. As the command increases logging, you should be able to witness whenever
`concocter` tries to update the content of its variables at a regular pace.