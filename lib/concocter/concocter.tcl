package require Tcl 8.6;

package require concocter::exec
package require concocter::var
package require concocter::output
package require concocter::sys

namespace eval ::concocter {
    variable version 0.1
    # This is a child namespace that will hold all globals that are necessary to
    # the module. Variables starting with a dash are options that can be set
    # from outside.
    namespace eval gvars {
        variable firsttime 1;  # First run marker
        variable -command  {}; # Program to execute
        variable -dryrun   0;  # Don't run anything
        variable -kill     {15 500 15 1000 15 1000 9 3000}
        variable -force    0;  # Force update always (use for debugging)
        variable -access   {}; # List of directories/file accessible to templaters
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
proc ::concocter::clamp {value {clamp 10} {postfix "..."}} {
    if { [string length $value] > $clamp } {
        return [string range $value 0 $clamp]$postfix
    }
    return $value
}


# ::update -- Perform one update
#
#       Perform one update of the templateed outputs, after having updated the
#       value of the variables. The templated outputs are only updated if any of
#       the variables changed since last time (or if we forced the update)
#
# Arguments:
#	vars	List of variables, this is to preserve file declaration order
#	force	Should we force and update all of the templates.
#
# Results:
#       The number of templated outputs that were properly executed.
#
# Side Effects:
#       Generates/overwrites files on disk.
proc ::concocter::update { vars { force off } } {
    set updated 0
    
    # Update the value of all variables.
    set changes 0
    foreach var $vars {
        if { [var::update $var] } {
            incr changes
        }
    }

    # Now run the templated outputs if we had any change or we were forced to
    # update. 
    if { $changes > 0 || [string is true $force] } {
        foreach out [output::outputs] {
            if { [output::update $out] } {
                incr updated
            }
        }
    } else {
        ::utils::debug DEBUG "Nothing to do, no variable had changed"
    }
    
    return $updated
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
proc ::concocter::Killer { i {here 0}} {
    variable gvars
    
    # Check if we have a running command right now
    set running [exec::running]
    if { [llength $running] > 0 } {
	set cmd [lindex $running 0]
	upvar \#0 $cmd CMD
    
	# Test if the process is still present. If we shouldn't perform that test,
	# then assume that it is present so we can try sending the signal anyway.
	if { $here } {
	    set processes [sys::processes]
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
	    set signal [string trimleft [lindex ${gvars::-kill} $i] "-"]
	    
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
		    exec::run -keepblanks -raw -- {*}${gvars::-command}
		}
	    } else {
		set respit [lindex ${gvars::-kill} [expr {$i+1}]]
		::utils::debug DEBUG "Sending signal $signal to $CMD(pid) and\
		                      waiting for $respit ms."

                sys::signal $signal $CMD(pid)

		# Check if the signal is one of the signals requesting for the
		# termination of the process. In which case we will be checking its
		# presence after the respit period.
                set deadtest [sys::deadly $signal]
	    
		# Pick up the respit period, sleep for that time and arrange to try
		# sending the next signal in the list.
		after $respit [namespace code [list Killer [expr {$i+2}] $deadtest]]
	    }
	} else {
	    # The process isn't there, we can simply restart it.
	    exec::run -keepblanks -raw -- {*}${gvars::-command}
	}
    } else {
	# The process isn't there, we can simply restart it.
	exec::run -keepblanks -raw -- {*}${gvars::-command}
    }
}


# ::concocter::loop -- Main loop
#
#       This is the main loop. It will update the value of the variables, update
#       the templated outputs based on these updated variable values and either
#       start the process under our command once or restart it whenever changes
#       to the output files have occured. 
#
# Arguments:
#	next	When to schedule next update loop (negative for one shot)
#
# Results:
#       None.
#
# Side Effects:
#       (re)start the process under our control
proc ::concocter::loop { next } {
    variable gvars
    
    # We force the update of the variables once and only once, i.e. the first
    # time that the program is run.
    set forceupdate [expr {$gvars::firsttime || [string is true ${gvars::-force}]}]
    set gvars::firsttime 0
    
    # Reschedule a change at once since we might wait infinitely below.
    if { $next > 0 } {
        after $next [namespace code [list loop $next]]
    }

    # Now perform a big update of variables and output files, and start the
    # process under our control once and only once or arrange to (re)start it.
    # Note that the implementation of the one-shot process start replaces this
    # process by the process specified as the process under our control.
    set vars [var::vars]
    if { [update $vars $forceupdate] > 0 } {
        if { [string is true ${gvars::-dryrun}]} {
	    ::utils::debug NOTICE "Would have executed: ${gvars::-command}"
	} else {
	    ::utils::debug NOTICE "Templates changed, now executing: ${gvars::-command}"
            if { [llength ${gvars::-command}] > 0 } {
                if { $next <= 0 } {
                    exec {*}${gvars::-command}
                } else {
                    # Check if we have a running command right now
                    Killer 0 1
                }
            } else {
                ::utils::debug WARN "Nothing to execute!"
            }
        }
    } else {
        ::utils::debug INFO "No changes to templates, nothing to do"
    }
}


proc ::concocter::settings {args} {
    variable gvars
    
    if { [llength $args] == 1 } {
        set opt [lindex $args 0]
        if { [info exists gvars::$opt] } {
            return [set gvars::$opt]
        } else {
            return -code error "$opt is not a setting"
        }
    } else {
        return [::utils::mset [namespace current]::gvars $args -]    
    }
}


package provide concocter $::concocter::version