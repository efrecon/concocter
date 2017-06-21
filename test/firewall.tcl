lappend auto_path [file join [file dirname [info script]] .. lib templater]
package require firewall
package require island

# Create an interp and allow it to access wiki.tcl.tk. We give it island access,
# just to exercise aliasing in the implementation.
set i [interp create -safe]
::island::add $i [file dirname [info script]]
::firewall::allow $i wiki.tcl.tk 80

# From http://wiki.tcl.tk/17394
proc get_package_load_command {name} {
    # Get the command to load a package without actually loading the package
    #
    # package ifneeded can return us the command to load a package but
    # it needs a version number. package versions will give us that
    set versions [package versions $name]
    if {[llength $versions] == 0} {
        # We do not know about this package yet. Invoke package unknown
        # to search
        {*}[package unknown] $name
        # Check again if we found anything
        set versions [package versions $name]
        if {[llength $versions] == 0} {
            error "Could not find package $name"
        }
    }
    return [package ifneeded $name [lindex $versions 0]]
}

# Read content of file implementing http library. This will only work for
# modules, really...
set fname [lindex [get_package_load_command http] end]
if { [file exists $fname] } {
    set fd [open $fname]
    set http [read $fd]
    close $fd
} else {
    puts stderr "Cannot find any implementation for http"
}
# Pass content of tcl_platform array to HTTP implementation, it needs it for
# creating the agent string.
$i eval [list array set ::tcl_platform [array get tcl_platform]]
# Pass content of HTTP implementation, this supposes a modern Tcl where HTTP is
# implemented as a single module.
$i eval $http
interp share {} stdout $i;   # Give away stdout so we can output data
$i eval {
    set t [::http::geturl http://wiki.tcl.tk/]
    if { [::http::data $t] ne "" } {
        puts "Properly downloaded [string length [::http::data $t]] char(s) from wiki.tck.tk"
    }
    # Make it fail on another host.
    set t [::http::geturl http://www.tcl.tk/]
}