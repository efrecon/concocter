##################
## Module Name     --  island.tcl
## Original Author --  Emmanuel Frecon - emmanuel.frecon@myjoice.com
## Description:
##
##      Package to a allow a safe interpreter to access islands of the
##      filesystem only, i.e. restricted directory trees within the
##      filesystem.
##
##################

package require Tcl 8.4


namespace eval ::island {
    namespace eval interps {};   # Will host information for interpreters
    variable version 0.1
}


proc ::island::Allowed { slave fname } {
    set vname [namespace current]::interps::[string map {: _} $slave]
    upvar \#0 $vname paths

    set abs_fname [::file dirname [::file normalize $fname/___]]
    foreach path $paths {
        if { [string first $path $abs_fname] == 0 } {
            return 1
        }
    }
    return 0
}


proc ::island::file { slave cmd args } {
    switch $cmd {
        atime -
        attributes -
        executable -
        exists -
        isdirectory -
        isfile -
        lstat -
        mtime -
        normalize -
        owned -
        readable -
        readlink -
        size -
        stat -
        system -
        type -
        writable {
            set fname [lindex $args 0]
            if { [Allowed $slave $fname] } {
                return [uplevel [linsert $args 0 $slave invokehidden file $cmd]]
            } else {
                return -code error "Access to $fname denied."
            }
        }
        channels -
        dirname -
        extension -
        join -
        nativename -
        pathtype -
        rootname -
        separator -
        split -
        tail -
        volumes {
            return [uplevel [linsert $args 0 $slave invokehidden file $cmd]]
        }
        copy -
        delete -
        rename -
        link {
            set idx [lsearch $args "--"]
            if { $idx >= 0 } {
                set paths [lrange $args [expr {$idx+1}] end]
            } else {
                if { [string index [lindex $args 0] 0] eq "-" } {
                    set paths [lrange $args 1 end]
                } else {
                    set paths $args
                }
            }
            foreach path $paths {
                if { ![Allowed $slave $path] } {
                    return -code error "Access to $path denied."
                }
            }
            return [uplevel [linsert $args 0 $slave invokehidden file $cmd]]
        }
        mkdir {
            foreach path $args {
                if { ![Allowed $slave $path] } {
                    return -code error "Access to $path denied."
                }
            }
            return [uplevel [linsert $args 0 $slave invokehidden file $cmd]]
        }
    }
}

proc ::island::open { slave args } {
    set fname [lindex $args 0]
    if { [string index [string trim $fname] 0] eq "|" } {
        return -code error "Execution of external programs disabled."
    }
    
    if { [Allowed $slave $fname] } {
        return [uplevel [linsert $args 0 $slave invokehidden open]]
    } else {
        return -code error "Access to $fname denied."
    }
}


proc ::island::Init { slave } {
    $slave alias file ::island::file $slave
    $slave alias open ::island::open $slave
}


proc ::island::add { slave path } {
    set vname [namespace current]::interps::[string map {: _} $slave]
    if { ![info exists $vname]} {
        Init $slave
    }
    upvar \#0 $vname paths
    lappend paths [::file dirname [::file normalize $path/___]]
}


proc ::island::reset { slave } {
    set vname [namespace current]::interps::[string map {: _} $slave]
    if { [info exists $vname] } {
        $slave alias file {}
        $slave alias open {}
        unset $vname
    }    
}

package provide island $::island::version