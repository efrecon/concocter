set libdir [file join [file dirname [info script]] .. lib templater]
lappend auto_path $libdir
package require island

set i [interp create -safe]
::island::add $i $libdir

puts [$i eval [list glob -directory $libdir *.tcl]]
$i eval [list cd $libdir]
puts [$i eval {
    set fd [open island.tcl]
    fconfigure $fd -buffering line
    set dta [read $fd]
    close $fd
    return $dta
}]
puts [$i eval [list file size island.tcl]]
