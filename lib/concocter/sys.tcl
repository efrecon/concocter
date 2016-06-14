namespace eval ::concocter::sys {
    variable version 0.1
    namespace eval gvars {
        variable -kill     "kill"
        variable -ps       "ps"
        variable -tasklist "tasklist"
        variable -taskkill "taskkill"
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
    set processes {};    # Will contain the list of processes, if possible

    # On windows, try through twapi, if we can, otherwise do this via tasklist
    if { [lsearch [split [::platform::generic] -] win32] >= 0 } {
        if { [catch {package require twapi} ver] == 0 } {
            set processes [::twapi::get_process_ids]
        } else {
            set sizes {}
            foreach l [[namespace parent]::exec::run -return -- [auto_execok ${gvars::-tasklist}]] {
                if { [llength $sizes] == 0 } {
                    set first [string trim [lindex $l 0]]
                    if { $first ne "" && [string trim $first =] eq "" } {
                        foreach s $l {
                            lappend sizes [string length $s]
                        }
                    }
                } else {
                    set i 0
                    set fields {}
                    foreach s $sizes {
                        set f [string range $l $i [expr {$i+$s}]]
                        incr i $s
                        incr i; # Space
                        lappend fields [string trim $f]
                    }
                    if { [string is integer -strict [lindex $fields 1]] } {
                        lappend processes [lindex $fields 1]
                    }
                }
            }
        }
    } else {
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
    }
    
    return $processes
}


proc ::concocter::sys::signal { signal pid } {
    variable gvars
    
    # Send the kill signal to the process. This uses syntax that will work for
    # most UNIXes.
    if { [lsearch [split [::platform::generic] -] win32] >= 0 } {
        if { ![deadly $signal] } {
            return -code error "No support for non-deadly signals on windows!"
        }
        
        if { [catch {package require twapi} ver] == 0 } {
            if { [deadly $signal on] } {
                ::twapi::end_process $pid -force
            } else {
                ::twapi::end_process $pid
            }
        } else {
            set killcmd [list [auto_execok ${gvars::-taskkill}] /pid $pid]
            if { [deadly $signal on] } {
                lappend killcmd /f
            }
            set res [[namespace parent]::exec::run -return -stderr -- {*}$killcmd]
            # If the process can only be terminated forcefully, do this at once,
            # do it as we are told!
            if { [string match *ERROR* $res] && [string match *forcefully*/F* $res] } {
                lappend killcmd /f
                set res [[namespace parent]::exec::run -return -stderr -- {*}$killcmd]
            }
        }
    } else {
        set killcmd [auto_execok ${gvars::-kill}]
        [namespace parent]::exec::run -return -- $killcmd -s $signal $pid
    }
}


proc ::concocter::sys::deadly { signal { forcefully off } } {
    set patterns [list 9 "*KILL"]
    if { ! $forcefully } {
        lappend patterns 15 "*TERM"
    }
    
    foreach ptn $patterns {
        if { [string match -nocase $ptn $signal] } {
            return 1
        }
    }
    return 0
}

package provide concocter::sys $::concocter::sys::version
