namespace eval ::concocter::sys {
    variable version 0.1
    namespace eval gvars {
        variable -kill "kill"
        variable -ps "ps"
        variable generator 0;  # Generator for identifiers
    }
}

package require concocter::exec

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
proc ::concocter::sys::processes {} {
    variable gvars
    
    ::utils::debug DEBUG "Getting list of processes..."
    set processes {}
    set skip 1
    foreach l [[namespace parent]::exec::run -return -- [auto_execok ${gvars::-ps}]] {
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


proc ::concocter::sys::signal { signal pid } {
    variable gvars
    
    # Send the kill signal to the process. This uses syntax that will work for
    # most UNIXes.
    set killcmd [auto_execok ${gvars::-kill}]
    [namespace parent]::exec::run -return -- $killcmd -s $signal $pid
}

proc ::concocter::sys::deadly { signal } {
    foreach ptn [list 15 9 "*TERM" "*KILL"] {
        if { [string match -nocase $ptn $signal] } {
            return 1
        }
    }
    return 0
}

package provide concocter::sys $::concocter::sys::version
