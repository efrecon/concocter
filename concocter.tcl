#! /usr/bin/env tclsh

set resolvedArgv0 [file dirname [file normalize $argv0/___]];  # Trick to resolve last symlink
set appname [file rootname [file tail $resolvedArgv0]]
if { $appname eq "main" } { set appname concocter }
set rootdir [file normalize [file dirname $resolvedArgv0]]
foreach ldir [list [file join $rootdir .. lib] \
        [file join $rootdir lib] \
        [file join $rootdir .. lib til] \
        [file join $rootdir lib til]] {
    if { [file isdirectory $ldir] } {
        lappend auto_path $ldir
    }
}
foreach ldir [list [file join $rootdir .. lib toclbox] \
        [file join $rootdir lib toclbox]] {
    if { [file isdirectory $ldir] } {
        ::tcl::tm::path add $ldir
    }
}

package require Tcl 8.6
package require utils
package require templater
package require http
package require base64
package require concocter

set version 1.1-dev
set prg_args {
    -vars     ""    "List of variables and their locations, preceed with @-sign for file indirection"
    -outputs  ""    "List of file paths and their templates, preceed with @-sign for file indirection"
    -update   "-1"  "Sequence of periods at which we check for variables, in seconds (negative to turn off)"
    -external ""    "External command to run at update interval, non-zero==force updating"
    -watchdog ""    "External command to send output from concocted command to, non-zero==force updating"
    -dryrun   "off" "Dry-run, do not execute, just perform templating"
    -kill     "15 500 15 1000 15 1000 9 3000" "Sequence of signals and respit periods"
    -verbose  "templater 3 utils 2 * 5"     "Verbosity specification for internal modules"
    -version  ""    "Print current version number and exit"
    -access   {}    "List of directories or files that templaters can access"
    -h        ""    "Print this help and exit"
    -plugins  "@%maindir%/lib/concocter/plugins.spc" "Plugin configuration"
}

# Add RESTish API only if we can find an HTTP server implementation
if { [catch {package require minihttpd} ver] == 0 } {
    lappend prg_args \
            -port "-1" "Port number for RESTish API"
}

# ::help:dump -- Dump help
#
#       Dump help based on the command-line option specification and
#       exit.
#
# Arguments:
#	hdr	Leading text to prepend to help message
#
# Results:
#       None.
#
# Side Effects:
#       Exit program
proc ::help:dump { { hdr "" } } {
    global appname version
    
    if { $hdr ne "" } {
        puts $hdr
        puts ""
    }
    puts "NAME:"
    puts "\t$appname v$version - Generates configuration files and (re)run another program"
    puts ""
    puts "USAGE"
    puts "\t${appname} \[options\] -- \[controlled program\]"
    puts ""
    puts "OPTIONS:"
    foreach { arg val dsc } $::prg_args {
        puts "\t[string range ${arg}[string repeat \  9] 0 9]$dsc (default: ${val})"
    }
    exit
}


# Did we ask for help at the command-line, print out all command-line
# options described above and exit.
::utils::pullopt argv opts
if { [::utils::getopt opts -h] } {
    ::help:dump
}
if { [::utils::getopt opts -version] } {
    puts "$version"
    exit
}

# Extract list of command-line options into array that will contain
# program state.  The description array contains help messages, we get
# rid of them on the way into the main program's status array.
array set CCT {}
foreach { arg val dsc } $prg_args {
    set CCT($arg) $val
}
for { set eaten "" } {$eaten ne $opts } {} {
    set eaten $opts
    foreach opt [array names CCT -*] {
        ::utils::pushopt opts $opt CCT
    }
}

# Remaining args? Dump help and exit
if { [llength $opts] > 0 } {
    ::help:dump "[lindex $opts 0] is an unknown command-line option!"
}

# Setup program verbosity and arrange to print out how we were started if
# relevant.
::utils::verbosity {*}$CCT(-verbose)
set startup "Starting $appname with following options\n"
foreach {k v} [array get CCT -*] {
    append startup "\t[string range $k[string repeat \  9] 0 9]: $v\n"
}
::utils::debug DEBUG [string trim $startup]

# Make sure we use TLS whenever we can, now that POODLE has been
# here... Then connect to all sources and start living forever.
if { [llength [toclbox https]] == 0 } {
    ::utils::debug WARN "No support for TLS and encryption available!"
}

# Read content of plugin specification file, if relevant, and register the
# variable plugins.
if { [string index $CCT(-plugins) 0] eq "@" } {
    set fname [::utils::resolve [string trim [string range $CCT(-plugins) 1 end]] \
            [list maindir $rootdir]]
    ::utils::debug INFO "Reading content of $fname for the plugins"
    set CCT(-plugins) [::utils::lread $fname -1 "plugins"]
}
foreach pspec $CCT(-plugins) {
    lassign $pspec ptn path
    ::concocter::var::plugin $ptn $path
}

# Read content of variable indirection file and create global variables in the
# ::var namespace that will hold information for the variables that we have
# created.
set fname ""
if { [string index $CCT(-vars) 0] eq "@" } {
    set fname [::utils::resolve [string trim [string range $CCT(-vars) 1 end]]]
    ::utils::debug INFO "Reading content of $fname for the variables"
    set CCT(-vars) [::utils::lread $fname -1 "variables"]
}
foreach vspec $CCT(-vars) {
    lassign $vspec k v dft
    ::concocter::var::new $k $v $dft $fname
}


# Read content of templating information and create global variables in the
# ::output namespace that will hold information for these templates and where
# they should output that we have created.
set fname "";   # We want a proper context file in outputs, if possible
if { [string index $CCT(-outputs) 0] eq "@" } {
    set fname [::utils::resolve [string trim [string range $CCT(-outputs) 1 end]]]
    ::utils::debug INFO "Reading content of $fname for the outputs"
    set CCT(-outputs) [::utils::lread $fname -1 "outputs"]
}
foreach ospec $CCT(-outputs) {
    lassign $ospec dst_path tpl_path
    ::concocter::output::new $dst_path $tpl_path $fname
}

::concocter::settings -command $argv
foreach opt [list -dryrun -kill -access] {
    ::concocter::settings $opt $CCT($opt)
}

if { [info exists CCT(-port)] && $CCT(-port) > 0 } {
    package require concocter::rest
    ::concocter::rest::server $CCT(-port)
}

# Recurrent (re)start of process whenever changes are detected or one shot.
::concocter::loop $CCT(-update) $CCT(-external) $CCT(-watchdog)

vwait forever
