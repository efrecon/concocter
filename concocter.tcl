#! /usr/bin/env tclsh

set resolvedArgv0 [file dirname [file normalize $argv0/___]]];  # Trick to resolve last symlink
set appname [file rootname [file tail $resolvedArgv0]]
set rootdir [file normalize [file dirname $resolvedArgv0]]
lappend auto_path [file join $rootdir .. lib] [file join $rootdir lib]

package require Tcl 8.6
package require utils
package require templater
package require http
package require tls
package require uri
package require base64

set prg_args {
    -vars    ""    "List of variables and their locations, preceed with @-sign for file indirection"
    -outputs ""    "List of file paths and their templates, preceed with @-sign for file indirection"
    -update  "-1"  "Period at which we check for variables, in seconds (negative to turn off)"
    -dryrun  "off" "Dry-run, do not execute, just perform templating"
    -kill    "15 500 15 1000 15 1000 9 3000" "Sequence of signals and respit periods"
    -verbose "templater 3 utils 2 * 5"     "Verbosity specification for internal modules"
    -h       ""    "Print this help and exit"
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
    global appname
    
    if { $hdr ne "" } {
	puts $hdr
	puts ""
    }
    puts "NAME:"
    puts "\t$appname - Generates configuration files and (re)run another program"
    puts ""
    puts "USAGE"
    puts "\t${appname}.tcl \[options\] -- \[controlled program\]"
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

# Extract list of command-line options into array that will contain
# program state.  The description array contains help messages, we get
# rid of them on the way into the main program's status array.
array set CCT {
    firsttime  1
}
foreach { arg val dsc } $prg_args {
    set CCT($arg) $val
}
for { set eaten "" } {$eaten ne $opts } {} {
    set eaten $opts
    foreach opt [array names CCT -*] {
        ::utils::getopt opts $opt CCT($opt) $CCT($opt)
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


# ::http::geturl_followRedirects -- geturl++
#
#       This procedure behaves exactly as the standard ::http::geturl, except
#       that it automatically follows refirects. It will follow redirects for a
#       finite number of times in order to always end.
#
# Arguments:
#	url	URL to get
#	args	Arguments to geturl
#
# Results:
#       HTTP token of the last URL that was got.
#
# Side Effects:
#       None.
proc ::http::geturl_followRedirects {url args} {
    for { set i 0 } { $i<20 } { incr i} {
        set token [eval [list http::geturl $url] $args]
        switch -glob -- [http::ncode $token] {
            30[1237] {
                if {[catch {array set OPTS $args}]==0} {
                    if { [info exists OPTS(-channel)] } {
                        seek $OPTS(-channel) 0 start
                    }
                }
            }
            default  { return $token }
        }
        upvar #0 $token state
        array set meta [set ${token}(meta)]
        if {![info exist meta(Location)]} {
            return $token
        }
        set url $meta(Location)
        unset meta
    }
}


# ::value:clamp -- Clamp long strings
#
#       Clamp long strings to some their beginning only, when their size is too
#       big. Strings that are longer than the allowed size are returned with a
#       postfix appended.
#
# Arguments:
#	value	String value to clamp
#	clamp	Max number of characters.
#	postfix	Postfix to append to long string to mark that they are longer
#
# Results:
#       The clamped string, with the postfix appended when the string was longer
#       than the maximum allowed size.
#
# Side Effects:
#       None.
proc ::value:clamp {value {clamp 10} {postfix "..."}} {
    if { [string length $value] > $clamp } {
        return [string range $value 0 $clamp]$postfix
    }
    return $value
}


# ::var:snapshot -- Variable snapshot
#
#       Return a snapshot of the current variables and their values. The
#       snapshot is an even-long list, where the variable names are surrounded
#       by the escape character string.
#
# Arguments:
#	names	Consider only variables which name matches this pattern
#	escape	Escape string to surround each variable name with
#
# Results:
#       An even-long list respresenting the snapshot of all matching variables.
#
# Side Effects:
#       None.
proc ::var:snapshot { {names *} {escape %}} {
    set mapper [list]
    foreach v [info vars ::var::*] {
	upvar \#0 $v VAR
	if { [string match $names $VAR(-name)] } {
	    lappend mapper ${escape}$VAR(-name)${escape} $VAR(value)
	}
    }
    return $mapper
}


# ::var:update -- Update the value of a variable
#
#       Update the value of a variable, depending on its source. When the source
#       starts with a "@" sign, the URL location (or a file) is fetched and its
#       content will be the value of the variable. Otherwise, this should be a
#       mathematical expression, which can depend on the value of other
#       variables. In that expression, the names of other variables should be
#       surrounded by the "%" sign.
#
# Arguments:
#	var	Identifier of the variable.
#
# Results:
#       1 if the content of the variable has changed and was updated, 0
#       otherwise.
#
# Side Effects:
#       None.
proc ::var:update { var } {
    upvar \#0 $var VAR

    set updated 0
    set VAR(previous) $VAR(value)
    if { [string index $VAR(-source) 0] eq "@" } {
        set location [string trim [string range $VAR(-source) 1 end]]
        ::utils::debug DEBUG "Reading content of $VAR(-name) from $location"
        if { [string match http*://* $location] } {
            array set URI [::uri::split $location]
            set hdrs [list]
            if { [info exists URI(user)] && $URI(user) ne "" } {
                lappend hdrs Authorization "Basic [base64::encode $URI(user):$URI(pwd)]"
            }
            set tok [::http::geturl_followRedirects $location -headers $hdrs]
            if { [::http::ncode $tok] >= 200 && [::http::ncode $tok] < 300 } {
                set VAR(value) [::http::data $tok]
                set updated [expr {$VAR(value) ne $VAR(previous)}]
                ::utils::debug DEBUG "Updated variable $VAR(-name) to [value:clamp $VAR(value)]"
            } else {
                ::utils::debug ERROR "Cannot get value from $location"
            }
            ::http::cleanup $tok
        } else {
            set fname [::utils::resolve $location]
            if { [catch {open $fname} fd] == 0 } {
                set VAR(value) [read $fd]
                set updated [expr {$VAR(value) ne $VAR(previous)}]
                close $fd
                ::utils::debug DEBUG "Updated variable $VAR(-name) to [value:clamp $VAR(value)]"
            } else {
                ::utils::debug ERROR "Cannot get value from $fname: $fd"                
            }
        }
    } else {
	# Math expression, there is no protection against cyclic dependencies or
	# order.
	set xpr [string map [var:snapshot] $VAR(-source)]
	if { [catch {expr $xpr} value] == 0 } {
	    set VAR(value) $value
            set updated [expr {$VAR(value) ne $VAR(previous)}]
	    ::utils::debug DEBUG "Updated variable $VAR(-name) to [value:clamp $VAR(value)]"
	} else {
	    ::utils::debug ERROR "Cannot evaluate math. expression $VAR(-source)"
	}
    }
    
    return $updated
}


# ::output:update -- Update an output file
#
#       Update the file that it pointed out by an output specification using the
#       template specified. The file path to both the output file and the
#       template can be sugared using a number of %-surrounded strings.
#       Recognised are all environments variables, all elements of the platform
#       array, all the variables and the variables dirname, fname and rootname
#       (refering to where from the output specficiation was read, if relevant).
#
# Arguments:
#	out	Identifier of the output
#
# Results:
#       1 if the output was generated properly using the template.
#
# Side Effects:
#       None.
proc ::output:update { out } {
    upvar \#0 $out OUT
    
    # Construct a variable map for substitution of %-surrounded strings in
    # paths. 
    set varmap [var:snapshot * ""]
    if { $OUT(-context) ne ""} {
	lappend varmap \
	    dirname [file dirname $OUT(-context)] \
	    fname [file tail $OUT(-context)] \
	    rootname [file rootname [file tail $OUT(-context)]]
    }

    # Resolve path for this time (note that we use the content of variables,
    # which might be handy to automatically generate different filenames)
    set dst_path [::utils::resolve $OUT(-destination) $varmap]
    set tpl_path [::utils::resolve $OUT(-template) $varmap]
    ::utils::debug INFO "Updating content of $dst_path using template at $tpl_path"
    
    # Create a template and execute it to output its result into the output file
    # path.
    set updated 0
    set tpl [::templater::new]
    ::templater::link $tpl $tpl_path
    foreach { k v } $varmap {
        ::templater::setvar $tpl $k $v
    }
    set res [::templater::render $tpl]
    if { [catch {open $dst_path w} fd] == 0 } {
        puts -nonewline $fd $res
        close $fd
        set updated 1
    } else {
        ::utils::debug ERROR "Cannot write to destination $dst_path"
    }
    ::templater::delete $tpl
    
    return $updated
}


# ::update -- Perform one update
#
#       Perform one update of the templateed outputs, after having updated the
#       value of the variables. The templated outputs are only updated if any of
#       the variables changed since last time (or if we forced the update)
#
# Arguments:
#	vars	List of variables, this is to preserve file declaration order
#	force	Should we force and update of the templates.
#
# Results:
#       The number of templated outputs that were properly executed.
#
# Side Effects:
#       Generates/overwrites files on disk.
proc ::update { vars { force off } } {
    set updated 0
    
    # Update the value of all variables.
    set changes 0
    foreach var $vars {
        if { [::var:update $var] } {
            incr changes
        }
    }

    # Now run the templated outputs if we had any change or we were forced to
    # update. 
    if { $changes > 0 || [string is true $force] } {
        foreach out [info vars ::output::*] {
            if { [output:update $out] } {
                incr updated
            }
        }
    } else {
        ::utils::debug DEBUG "Nothing to do, no variable had changed"
    }
    
    return $updated
}


# ::POpen4 -- Pipe open
#
#       This procedure executes an external command and arranges to
#       redirect locally assiged channel descriptors to its stdin,
#       stdout and stderr.  This makes it possible to send input to
#       the command, but also to properly separate its two forms of
#       outputs.
#
# Arguments:
#	args	Command to execute
#
# Results:
#       A list of four elements.  Respectively: the list of process
#       identifiers for the command(s) that were piped, channel for
#       input to command pipe, for regular output of command pipe and
#       channel for errors of command pipe.
#
# Side Effects:
#       None.
proc ::POpen4 { args } {
    foreach chan {In Out Err} {
        lassign [chan pipe] read$chan write$chan
    } 

    set pid [exec {*}$args <@ $readIn >@ $writeOut 2>@ $writeErr &]
    chan close $writeOut
    chan close $writeErr

    foreach chan [list stdout stderr $readOut $readErr $writeIn] {
        chan configure $chan -buffering line -blocking false
    }

    return [list $pid $writeIn $readOut $readErr]
}


# ::LineRead -- Read line output from started commands
#
#       This reads the output from commands that we have started, line
#       by line and either prints it out or accumulate the result.
#       Properly mark for end of output so the caller will stop
#       waiting for output to happen.  When outputing through the
#       logging facility, the procedure is able to recognise the
#       output of docker-machine commands (which uses the logrus
#       package) and to convert between loglevels.
#
# Arguments:
#	c	Identifier of command being run
#	fd	Which channel to read (refers to index in command)
#
# Results:
#       None.
#
# Side Effects:
#       Read lines, outputs
proc ::LineRead { c fd } {
    upvar \#0 $c CMD

    set line [gets $CMD($fd)]

    # Respect -keepblanks and output or accumulate in result
    if { ( !$CMD(keep) && [string trim $line] ne "") || $CMD(keep) } {
	if { $CMD(back) } {
	    if { ( $CMD(outerr) && $fd eq "stderr" ) || $fd eq "stdout" } {
		lappend CMD(result) $line
	    }
	} elseif { $CMD(relay) } {
	    puts $fd $line
	}
    }

    # On EOF, we stop this very procedure to be triggered.  If there
    # are no more outputs to listen to, then the process has ended and
    # we are done.
    if { [eof $CMD($fd)] } {
	fileevent $CMD($fd) readable {}
	if { [fileevent $CMD(stdout) readable] eq "" \
		 && [fileevent $CMD(stderr) readable] eq "" } {
	    set CMD(done) 1
	}
    }
}


proc ::Run { args } {
    # Isolate -- that will separate options to procedure from options
    # that would be for command.  Using -- is MANDATORY if you want to
    # specify options to the procedure.
    set sep [lsearch $args "--"]
    if { $sep >= 0 } {
        set opts [lrange $args 0 [expr {$sep-1}]]
        set args [lrange $args [expr {$sep+1}] end]
    } else {
        set opts [list]
    }

    # Create an array global to the namespace that we'll use for
    # synchronisation and context storage.
    namespace eval ::command {}
    set c [::utils::identifier ::command::]
    upvar \#0 $c CMD
    set CMD(id) $c
    set CMD(command) $args
    ::utils::debug DEBUG "Executing $CMD(command) and capturing its output"

    # Extract some options and start building the
    # pipe.  As we want to capture output of the command, we will be
    # using the Tcl command "open" with a file path that starts with a
    # "|" sign.
    set CMD(keep) [::utils::getopt opts -keepblanks]
    set CMD(back) [::utils::getopt opts -return]
    set CMD(outerr) [::utils::getopt opts -stderr]
    set CMD(relay) [::utils::getopt opts -raw]
    set CMD(done) 0
    set CMD(result) {}

    # Kick-off the command and wait for its end
    lassign [POpen4 {*}$args] CMD(pid) CMD(stdin) CMD(stdout) CMD(stderr)
    fileevent $CMD(stdout) readable [namespace code [list LineRead $c stdout]]
    fileevent $CMD(stderr) readable [namespace code [list LineRead $c stderr]]
    vwait ${c}(done);   # Wait for command to end

    ::utils::debug TRACE "Command $CMD(command) has ended, cleaning up and returning"
    catch {close $CMD(stdin)}
    catch {close $CMD(stdout)}
    catch {close $CMD(stderr)}

    set res $CMD(result)
    unset $c
    return $res
}


# ::processes -- List of running processes
#
#       Return the list of running process identifiers. This attempts to cope
#       with all possible corner cases, assuming that the process identifier is
#       the first integer present as part of each line returned by ps. The
#       current implementation covers most cases, including busybox-based
#       implementations.
#
# Arguments:
#       None.
#
# Results:
#       List of currently running processes.
#
# Side Effects:
#       Uses the UNIX command ps, this will not work on Windows.
proc ::processes {} {
    ::utils::debug DEBUG "Getting list of processes..."
    set processes {}
    set skip 1
    foreach l [Run -return -- [auto_execok ps]] {
	if { $skip } {
	    # Skip header!
	    set skip 0
	} else {
	    foreach p [string trim $l] {
		if { [string is integer -strict $p]} {
		    lappend processes $p
		    break
		}
	    }
	}
    }
    return $processes
}


# ::killer -- Sequentially kill the current process.
#
#       This procedure is meant to be sequentially called using after. It will
#       send, in turns, the signals specified as part of the -kill command-line
#       option and wait for the amount of milliseconds specified as part of the
#       same option. The command treats "killing" signals a bit differently as
#       it checks that the process still exists and ends up as soon as the
#       process has properly ended. However, it is possible to send USR1 or HUP
#       for processes that support reloading their configuration files when
#       receiving these type of signals.
#
# Arguments:
#	i	Index within the -kill command-line list (even!)
#	here	Should we test if the process still is present?
#
# Results:
#       None.
#
# Side Effects:
#       Send signals to the process under our control in turns.
proc ::killer { i {here 0}} {
    global CCT argv
    
    # Check if we have a running command right now
    set running [info vars ::command::*]
    if { [llength $running] > 0 } {
	set cmd [lindex $running 0]
	upvar \#0 $cmd CMD
    
	# Test if the process is still present. If we shouldn't perform that test,
	# then assume that it is present so we can try sending the signal anyway.
	if { $here } {
	    set processes [processes]
	    ::utils::debug TRACE "Looking for $CMD(pid) within $processes"
	    set present [expr {[lsearch $processes $CMD(pid)] >= 0}]
	} else {
	    set present 1
	}
	
	if { $present } {
	    ::utils::debug DEBUG "Process under our control $CMD(command) still at\
				  PID: $CMD(pid)"	    
	}
	
	if { $present } {
	    # Get which signal to send to the process from the command line arguments.
	    set signal [string trimleft [lindex $CCT(-kill) $i] "-"]
	    
	    if { $signal eq "" } {
		# No signal means that we are actually at the end of the list. If we
		# had requested for process death in the previous phase, and since
		# the process is still there, we don't know how to proceed and exit.
		# Otherwise, things are fine, we can simply start a new process.
		if { $here } {
		    ::utils::debug CRITICAL "Could not manage to kill process"
		    exit
		} else {
		    ::utils::debug INFO "All signals sent, restarting process"
		    Run -keepblanks -raw -- {*}$argv
		}
	    } else {
		set respit [lindex $CCT(-kill) [expr {$i+1}]]
		::utils::debug DEBUG "Sending signal $signal to $CMD(pid) and\
		                      waiting for $respit ms."

		# Send the kill signal to the process. This uses syntax that will
		# work for most UNIXes.
		set killcmd [auto_execok "kill"]
		Run -return -- $killcmd -s $signal $CMD(pid)
		
		# Check if the signal is one of the signals requesting for the
		# termination of the process. In which case we will be checking its
		# presence after the respit period.
		set deadtest 0
		foreach ptn [list 15 9 "*TERM" "*KILL"] {
		    if { [string match -nocase $ptn $signal] } {
			set deadtest 1
		    }
		}        
	    
		# Pick up the respit period, sleep for that time and arrange to try
		# sending the next signal in the list.
		after $respit [list ::killer [expr {$i+2}] $deadtest]
	    }
	} else {
	    # The process isn't there, we can simply restart it.
	    Run -keepblanks -raw -- {*}$argv
	}
    } else {
	# The process isn't there, we can simply restart it.
	Run -keepblanks -raw -- {*}$argv	
    }
}


# ::loop -- Main loop
#
#       This is the main loop. It will update the value of the variables, update
#       the templated outputs based on these updated variable values and either
#       start the process under our command once or restart it whenever changes
#       to the output files have occured. 
#
# Arguments:
#	vars	List of variables, this is to respect file order
#	next	When to schedule next update loop (negative for one shot)
#
# Results:
#       None.
#
# Side Effects:
#       (re)start the process under our control
proc ::loop { vars next } {
    global CCT argv
    
    # We force the update of the variables once and only once, i.e. the first
    # time that the program is run.
    set forceupdate $CCT(firsttime)
    set CCT(firsttime) 0
    
    # Reschedule a change at once since we might wait infinitely below.
    if { $next > 0 } {
        after $next [list ::loop $vars $next]
    }

    # Now perform a big update of variables and output files, and start the
    # process under our control once and only once or arrange to (re)start it.
    # Note that the implementation of the one-shot process start replaces this
    # process by the process specified as the process under our control.
    if { [::update $vars $forceupdate] > 0 } {
        if { [string is true $CCT(-dryrun)]} {
	    ::utils::debug NOTICE "Would have executed: $argv"
	} else {
	    ::utils::debug NOTICE "Templates changed, now executing: $argv"
            if { [llength $argv] > 0 } {
                if { $next <= 0 } {
                    exec {*}$argv
                } else {
                    # Check if we have a running command right now
                    killer 0 1
                }
            } else {
                ::utils::debug WARN "Nothing to execute!"
            }
        }
    } else {
        ::utils::debug INFO "No changes to templates, nothing to do"
    }
}



# Initialise HTTP module to use at least TLS1.0
::http::register https 443 [list ::tls::socket -tls1 1]

# Read content of variable indirection file and create global variables in the
# ::var namespace that will hold information for the variables that we have
# created.
if { [string index $CCT(-vars) 0] eq "@" } {
    set fname [::utils::resolve [string trim [string range $CCT(-vars) 1 end]]]
    ::utils::debug INFO "Reading content of $fname for the variables"
    set CCT(-vars) [::utils::lread $fname -1 "variables"]
}
set vars [list]
foreach vspec $CCT(-vars) {
    lassign $vspec k v dft
    namespace eval ::var {}
    set var [::utils::identifier ::var::]
    upvar \#0 $var VAR
    set VAR(-name) $k
    set VAR(-source) $v
    set VAR(value) $dft
    lappend vars $var
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
    namespace eval ::output {}
    set vname [::utils::identifier ::output::]
    upvar \#0 $vname OUT
    set OUT(-destination) $dst_path
    set OUT(-template) $tpl_path
    set OUT(-context) $fname
}


# Recurrent (re)start of process whenever changes are detected or one shot.
if { $CCT(-update) <= 0 } {
    loop $vars -1
} else {
    set next [expr {int($CCT(-update)*1000)}]
    loop $vars $next
}
vwait forever