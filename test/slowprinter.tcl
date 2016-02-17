#! /usr/bin/env tclsh

proc dumpline {fd max} {
    if { [eof $fd] } {
        close $fd
        exit
    } else {
        set line [gets $fd]
        puts stdout $line
        set next [expr {int(rand()*$max)}]
        after $next [list ::dumpline $fd $max]
    }
}
set fd [open [lindex $argv 0]]
if { [string is integer -strict [lindex $argv 1]] } {
    after idle [list ::dumpline $fd [lindex $argv 1]]
} else {
    after idle [list ::dumpline $fd 500]
}
vwait forever