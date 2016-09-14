#! /usr/bin/env tclsh

# Test this through issuing: -external reload@%progdir%/test/hook.tcl on the
# command line when starting concocter. To demonstrate regular argument passing,
# you could do -external %progdir%/test/hook.tcl which will create a new interp
# and source the script each time instead (and this, because of the body of the
# main script that calls this procedure)
proc reload { pid {force 0} } {
    variable counter
    
    incr counter
    if { $force || $pid < 0 } {
        set reloading 1
    } else {
        set reloading [expr {rand()<0.05}]
    }
    if { $reloading } {
        puts ""
        puts "***"
        puts "*** Forcing reload of templates ($counter) ***"
        puts "***"
        puts ""
    }
    return $reloading
}

# Test this through issuing: -watchdog capture@%progdir%/test/hook.tcl on the
# command line when starting concocter.
proc capture { fd line } {
    return [reload 0]; # Don't really take a decision using log line, just let
                       # randomness decide.
}

return [reload [lindex $argv 0]]