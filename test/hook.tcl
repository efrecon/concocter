#! /usr/bin/env tclsh

proc reload { {force 0} } {
    variable counter
    
    incr counter
    if { $force } {
        set reloading 1
    } else {
        set reloading [expr {rand()<0.5}]
    }
    if { $reloading } {
        puts "*** Forcing reload of templates ($counter) ***"
    }
    return $reloading
}

return [reload]