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
        variable loop "";      # Timer identifier for main loop
        variable -command  {}; # Program to execute
        variable -dryrun   0;  # Don't run anything
        variable -kill     {15 500 15 1000 15 1000 9 3000}
        variable -force    0;  # Force update always (use for debugging)
        variable -access   {}; # List of directories/file accessible to templaters
        variable -clamp    15; # Max default number of characters for clamping output
        variable interps   [dict create]
    }
}


# ::concocter::clamp -- Clamp long strings
#
#       Clamp long strings to some their beginning only, when their size is too
#       big. Strings that are longer than the allowed size are returned with a
#       postfix appended.
#
# Arguments:
#	value	String value to clamp
#	clamp	Max number of characters (negative for module default, 0 for none)
#	postfix	Postfix to append to long string to mark that they are longer
#
# Results:
#       The clamped string, with the postfix appended when the string was longer
#       than the maximum allowed size.
#
# Side Effects:
#       None.
proc ::concocter::clamp {value {clamp -1} {postfix "..."}} {
    variable gvars
    
    if { $clamp < 0 } {
        set clamp ${gvars::-clamp}
    }
    
    if { $clamp > 0 && [string length $value] > $clamp } {
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
#	capture	Command to call to capture output log lines
#
# Results:
#       None.
#
# Side Effects:
#       Send signals to the process under our control in turns.
proc ::concocter::Killer { i {here 0} {capture {}}} {
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
	    ::utils::debug DEBUG "Process under our control $CMD(command) is at\
				  PID: $CMD(pid)"	    
	}
	
	if { $present } {
	    # Get which signal to send to the process from the command line arguments.
	    set signal [string trimleft [lindex ${gvars::-kill} $i] "-"]
	    
	    if { $signal eq "" } {
		# No signal means that we are actually at the end of the list. If we
		# had requested for process death in the previous phase, and since
		# the process is still there, we don't know how to proceed and exit.
                # Otherwise, things are fine and since the (last) signal wasn't
                # deadly we just don't have anything else to do.
		if { $here } {
		    ::utils::debug CRITICAL "Could not manage to kill process"
		    exit
		} else {
		    #::utils::debug INFO "All signals sent, restarting process"
		    #exec::run -keepblanks -raw -- {*}${gvars::-command}
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
		after $respit [namespace code [list Killer [expr {$i+2}] $deadtest $capture]]
	    }
	} else {
	    # The process isn't there, we can simply restart it.
            if { [llength $capture] } {
                exec::run -keepblanks -raw -capture [namespace code [list WatchDog $capture]] -- {*}${gvars::-command}
            } else {
                exec::run -keepblanks -raw -- {*}${gvars::-command}
            }
	}
    } else {
        # The process isn't there, we can simply restart it.
        if { [llength $capture] } {
            exec::run -keepblanks -raw -capture [namespace code [list WatchDog $capture]] -- {*}${gvars::-command}
        } else {
            exec::run -keepblanks -raw -- {*}${gvars::-command}
        }
    }
}


# ::concocter::WatchDog -- Log lines watchdog.
#
#       This procedure called with every captured log lines that is output by
#       the program that is under our control, whenever necessary. When the
#       command that is associated to the hook (see ::concocter::hook) returns a
#       positive value, the program under our control will be restarted.
#
# Arguments:
#	cspec	See ::concocter::hook
#	fd	Where the line was output (stdout or stderr)
#	line	Log line that was captured.
#
# Results:
#       None.
#
# Side Effects:
#       Restart or start signals to process under our control
proc ::concocter::WatchDog { cspec fd line } {
    variable gvars
    
    set status [hook $cspec DEBUG $fd $line]
    if { $status } {
        reload
    }
}


proc ::concocter::reload { } {
    variable gvars
    
    if { $gvars::loop ne "" } {
        # Simulate that this was the first time to check all variables again
        # and rerun the main loop, which we've just captured from the
        # scheduled command.
        set gvars::firsttime 1
        set cmd [lindex [after info $gvars::loop] 0];  # Capture after'd command
        eval {*}$cmd
    }
}


# ::concocter::hook -- Call extern hook.
#
#       This procedure can call external hooks to decide whether the program
#       under our control should be restarted or not. This only implements
#       decision-making, restarting behaviour is elsewhere. There are three
#       different sorts of command specifications. In its simplest form, this is
#       any external command (not tcl), which will be a command-line
#       specification to which the additional arguments from the procedure call
#       are added. Its return value will be the decision to make. Whenever this
#       is a tcl script, if it contains xxx@ leading the script path, xxx will
#       be considered as a procedure (and arguments) within that script. The
#       name of the procedure is separated from fixed arguments using ! marks.
#       Additional arguments (args variable) are passed to the procedure after
#       these. In that case, one interpreter will be created and the procedure
#       will be called on and on as necessary (which enables to keep state in
#       the interpreter). If no @ sign was found, interpreter creation will
#       occur each time. The arguments to the script on the command line are
#       passed as argv/argc pairs to those interpreters.
#
# Arguments:
#	cspec	See above
#	lvl	Debug level at which to output execution messages
#	args	Arguments (dynamic) passed to program or procedure.
#
# Results:
#       negative boolean whenever the program shouldn't be restarted, positive
#       otherwise
#
# Side Effects:
#       Might call external program!
proc ::concocter::hook { cspec lvl args } {
    variable gvars
    
    set cspec [string trim $cspec]
    if { $cspec eq "" } {
        return 0
    }

    set prg [lindex $cspec 0]
    if { [string equal -nocase [file extension $prg] ".tcl"] } {
        # Specific treatment for Tcl scripts, since we are able to call
        # procedures in them, etc. We'll create interpreters to run them in, see
        # below for details.
        set arobas [string first @ $prg]
        if { $arobas >= 0 } {
            # When we have an @ in the string, we understand this as a procedure
            # to call within an interpreter (source from the file after the @
            # sign). In this case, we keep the interpreter from one call to the
            # next, so it can store which ever state it needs to.
            set script [string trim [string range $prg [expr {$arobas+1}] end]]

            # Create the interpreter once, we'll reuse it
            if { ![dict exists $gvars::interps $script] } {
                set itrp [interp create]
                $itrp eval [list set ::argv0 $prg]
                $itrp eval [list set ::argv [lrange $cspec 1 end]]
                $itrp eval [list set ::argc [llength [lrange $cspec 1 end]]]
                if { [catch {$itrp eval source [::utils::resolve $script]} res] != 0 } {
                    ::utils::debug ERROR "Cannot load script from $script: $res"
                    interp delete $itrp
                    return 0
                }
                dict set gvars::interps $script $itrp
            }
            
            # We have an interpreter. Split what is before the @ sign along the
            # possible ! sign (to be able to give parameters to the procedure,
            # if necessary) and use the return code of the procedure.
            if { [dict exists $gvars::interps $script] } {
                set itrp [dict get $gvars::interps $script]
                set call [concat [split [string range $cspec 0 [expr {$arobas-1}]] !] $args]
                ::utils::debug $lvl "Executing hook $call from $script for update forcing"
                try {
                    set status [$itrp eval $call]
                } on error {res} {
                    ::utils::debug WARN "Cannot execute $call in interp: $res"
                    set status 0
                }
                
                return $status
            }
        } else {
            # When the specification is only a tcl script, we'll source it in a
            # new interpreter on and on. We use the return value of the last
            # command as the status.
            ::utils::debug $lvl "Executing hook from $cspec for update forcing"
            set itrp [interp create]
            set arglist [concat [lrange $cspec 1 end] $arg]
            $itrp eval [list set ::argv0 $prg]
            $itrp eval [list set ::argv $arglist]
            $itrp eval [list set ::argc [llength $arglist]]
            try {
                set status [$itrp eval [list source [::utils::resolve $prg]]]
            } on error {res} {
                ::utils::debug ERROR "Cannot execute Tcl code at $cspec: $res"
                set status 0
            } finally {
                interp delete $itrp
            }
            
            return $status
        }
    } else {
        # Otherwise, we execute the command and use its result to know what to
        # do.
        ::utils::debug $lvl "Executing hook at $cspec for update forcing"
        try {
            set res [exec -ignorestderr -- {*}[concat $cspec $args]]
            set status 0
        } trap CHILDSTATUS {res options} {
            set status [lindex [dict get $options -errorcode] 2]
        } on error {res} {
            ::utils::debug ERROR "Cannot execute command hook: $res"
            set status -1
        }
        return $status
    }
    
    return 0; # Failsafe for all
}


# ::concocter::loop -- Main loop
#
#       This is the main loop. It will update the value of the variables, update
#       the templated outputs based on these updated variable values and either
#       start the process under our command once or restart it whenever changes
#       to the output files have occured. 
#
# Arguments:
#	nexts	When to schedule next update loop (negative for one shot)
#	hook	Command to call for restart decision at each loop
#	watchdog	Command to call with each log line.
#	idx	Index in nexts periods.
#
# Results:
#       None.
#
# Side Effects:
#       (re)start the process under our control
proc ::concocter::loop { nexts {hook ""} {watchdog ""} {idx 0}} {
    variable gvars
    
    # We force the update of the variables once and only once, i.e. the first
    # time that the program is run.
    set forceupdate [expr {$gvars::firsttime || [string is true ${gvars::-force}]}]
    set firsttime $gvars::firsttime
    set gvars::firsttime 0
    
    # Reschedule a change at once since we might wait infinitely below.
    set next [lindex $nexts $idx]
    if { $next > 0 } {
        set next [expr {int(1000*$next)}]
        if { $idx < [llength $nexts]-1} {
            incr idx
        }
        if { $gvars::loop ne "" } {
            catch {after cancel $gvars::loop}
        }
        set gvars::loop [after $next [namespace code [list loop $nexts $hook $watchdog $idx]]]

        # Call external hook command
        if { [hook $hook INFO] } {
            set forceupdate 1
        }
    }
    

    # Now perform a big update of variables and output files, and start the
    # process under our control once and only once or arrange to (re)start it.
    # Note that the implementation of the one-shot process start replaces this
    # process by the process specified as the process under our control.
    set vars [var::vars]
    if { [update $vars $forceupdate] > 0 || $firsttime } {
        if { [string is true ${gvars::-dryrun}]} {
	    ::utils::debug NOTICE "Would have executed: ${gvars::-command}"
	} else {
	    ::utils::debug NOTICE "Templates changed, now executing: ${gvars::-command}"
            if { [llength ${gvars::-command}] > 0 } {
                if { $next < 0 } {
                    exec {*}${gvars::-command}
                } else {
                    # Check if we have a running command right now
                    Killer 0 1 $watchdog
                }
            } else {
                ::utils::debug WARN "Nothing to execute!"
            }
        }
    } else {
        ::utils::debug INFO "No changes to templates, nothing to do"
    }
}


proc ::concocter::settings { args } {
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


# Unused.
proc ::concocter::Hash {str {modulo 2147483647} } {
    if { $str eq "" } {
        return 0
    }

    set inited 0
    set hash 0
    foreach c [split $str {}] {
        set val [scan $c %c]
        if { $inited } {
            set hash [expr {($hash+int(rand()*$modulo)+$val)%$modulo}]
        } else {
            set hash [expr {($hash+int(srand($val)*$modulo)+$val)%$modulo}]
            set inited 1
        }
    }
    return $hash
}

package provide concocter $::concocter::version