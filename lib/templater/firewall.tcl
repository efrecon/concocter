##################
## Module Name     --  firewall.tcl
## Original Author --  Emmanuel Frecon - emmanuel.frecon@myjoice.com
## Description:
##
##      Package to a allow a safe interpreter to access islands of the network,
##      i.e. this implements a client firewall.
##
##################

package require Tcl 8.4


namespace eval ::firewall {
    namespace eval interps {};   # Will host information for interpreters
    namespace export {[a-z]*};   # Convention: export all lowercase 
    catch {namespace ensemble create}
    variable version 0.1
}


# ::firewall::allow -- Allow host and port (patterns)
#
#       Add a host and port pattern to the list of remote locations that are
#       explicitely allowed for access to a slave interpreter. 
#
# Arguments:
#	slave	Identifier of the slave to control
#	host	Host/IP pattern
#	port	Port pattern
#
# Results:
#       The current context of allowed and denied patterns
#
# Side Effects:
#       None.
proc ::firewall::allow { slave { host "" } {port *} } {
    set vname [namespace current]::interps::[string map {: _} $slave]
    if { ![info exists $vname]} {
        Init $slave
    }
    upvar \#0 $vname context
    dict lappend context allow $host $port
    return [dict filter $context key allow deny]
}


# ::firewall::deny -- Deny host and port (patterns)
#
#       Add a host and port pattern to the list of remote locations that are
#       explicitely denied for access to a slave interpreter. Denial is tested
#       after allowance, meaning that arguments to this procedure are meant to
#       restrict away from the allowance list.
#
# Arguments:
#	slave	Identifier of the slave to control
#	host	Host/IP pattern
#	port	Port pattern
#
# Results:
#       The current context of allowed and denied patterns
#
# Side Effects:
#       None.
proc ::firewall::deny { slave { host "*" } {port *} } {
    set vname [namespace current]::interps::[string map {: _} $slave]
    if { ![info exists $vname]} {
        Init $slave
    }
    upvar \#0 $vname context
    dict lappend context deny $host $port
    return [dict filter $context key allow deny]
}


# ::firewall::reset -- Cleanup
#
#       Remove all access path allowance and arrange for the interpreter to be
#       able to return to the regular safe state.
#
# Arguments:
#	slave	Identifier of the slave
#
# Results:
#       None.
#
# Side Effects:
#       None.
proc ::firewall::reset { slave } {
    set vname [namespace current]::interps::[string map {: _} $slave]
    if { [info exists $vname] } {
        foreach cmd [list socket fconfigure encoding] {
            if { [dict exists $context aliases $cmd] } {
                $slave alias $cmd [dict get $context aliases $cmd]
            } else {
                $slave alias $cmd {}
            }
        }
        unset $vname
    }    
}



########################
##
## Procedures below are internal to the implementation.
##
########################


# ::firewall::Allowed -- Check access restrictions
#
#       Check that the file name passed as an argument is within the islands of
#       the filesystem that have been registered through the add command for a
#       given (safe) interpreter. The path is fully normalized before testing
#       against the islands, which themselves are fully normalized.
#
# Arguments:
#	slave	Identifier of the slave under out control
#	fname	(relative) path to the file to test
#
# Results:
#       1 if access is allowed, 0 otherwise
#
# Side Effects:
#       None.
proc ::firewall::Allowed { slave host port } {
    set vname [namespace current]::interps::[string map {: _} $slave]
    upvar \#0 $vname context

    set allowed 0;  # Default is to deny everything!
    if { [dict exists $context allow] } {
        foreach { h p } [dict get $context allow] {
            if { [string match -nocase $h $host] && [string match $p $port] } {
                set allowed 1
                break
            }
        }
    }
    if { $allowed && [dict exists $context deny] } {
        foreach { h p } [dict get $context deny] {
            if { [string match -nocase $h $host] && [string match $p $port] } {
                set allowed 0
                break
            }
        }
    }
    return $allowed
}


# ::firewall::Invoke -- Expose back a command
#
#       This procedure allows to callback a command that would typically have
#       been hidden from a slave interpreter. It does not "interp expose" but
#       rather calls the hidden command, so we can easily revert back. If
#       instead the command was already aliased to another command once we took
#       it over, call the command that it was aliased to in order to keep the
#       proper chain of callbacks.
#
# Arguments:
#	slave	Identifier of the slave under our control
#	cmd		Hidden command to call
#	args	Arguments to the glob command.
#
# Results:
#       As of the hidden command to call
#
# Side Effects:
#       As of the hidden command to call
proc ::firewall::Invoke { slave cmd args } {
    set vname [namespace current]::interps::[string map {: _} $slave]
    upvar \#0 $vname context

    if { [info exists $vname] && [dict exists $context aliases $cmd] } {
        # Aliased command is to be called in same interpreter as the the main
        # interpreter
        return [uplevel [dict get $context aliases $cmd] $args]
    } elseif { $slave eq "" } {
        return [uplevel [linsert $args 0 $cmd]]
    } else {
        return [uplevel [linsert $args 0 $slave invokehidden $cmd]]
    }
}


# ::firewall::Socket -- Restricted socket
#
#       Parses the options and arguments to the glob command to discover which
#       paths it tries to access and only return the results of its execution
#       when these path are within the allowed islands of the filesystem.
#
# Arguments:
#	slave	Identifier of the slave under our control
#	args	Arguments to the glob command.
#
# Results:
#       As of the socket command.
#
# Side Effects:
#       As of the socket command.
proc ::firewall::Socket { slave args } {
    set noargs [list -async]
    set opts [list]
    set within ""
    for {set i 0} {$i < [llength $args]} {incr i} {
        set itm [lindex $args $i]
        if { $itm eq "--" } {
            incr i; break
        } elseif { [string index $itm 0] eq "-" } {
            # Segragates between options that take a value and options that
            # have no arguments and are booleans.
            if { [lsearch $noargs $itm] < 0 } {
                incr i;  # Jump over argument
                switch -glob -- $itm {
                    "-myp*" -
                    "-mya*" {
                        # Capture -myhost and -myport
                        lappend opts $itm [lindex $args $i]
                    }
                    "-s*" {
                        return -code error "Server socket not allowed!"
                    }
                }
            } else {
                lappend opts $itm
            }
        } else {
            break
        }
    }

    # cut off remaining arguments and check for allowance of host and port
    # specified there.
    set args [lrange $args $i end]
    if { [llength $args] < 2 } {
        return -code error "Missing host or port specification!"
    }
    foreach {host port} $args break
    if { ![Allowed $slave $host $port] } {
        return -code error "Access to ${host}:${port} prevented by firewall"
    }

    # Reconstruct call and pass further
    lappend opts $host $port; # Reinsert host and port at end of options
    return [uplevel [linsert $args 0 [namespace current]::Invoke $slave socket]]
}


# ::firewall::Alias -- Careful aliasing
#
#       Create an alias to an existing into this library, making sure to
#       remember where the command was already aliased to whenever relevant.
#
# Arguments:
#	slave	Identifier of the slave to control
#	cmd 	Command to alias
#	args	Additional arguments to command
#
# Results:
#       None.
#
# Side Effects:
#       None.
proc ::firewall::Alias { slave cmd args } {
    set vname [namespace current]::interps::[string map {: _} $slave]
    upvar \#0 $vname context

    if { ![info exists $vname] || ![dict exists $context aliases $cmd] } {
        set alias [$slave alias $cmd]
        if { $alias ne "" } {
            dict set context aliases $cmd $alias
        }
    }
    return [uplevel [linsert $args 0 $slave alias $cmd]]
}


# ::firewall::Init -- Initialise interp
#
#       Initialise slave interpreter so that it will be able to perform some
#       file operations, but only within some islands of the filesystem.
#
# Arguments:
#	slave	Identifier of the slave to control
#
# Results:
#       None.
#
# Side Effects:
#       None.
proc ::firewall::Init { slave } {
    Alias $slave socket ::firewall::Socket $slave
    Alias $slave fconfigure ::firewall::Invoke $slave fconfigure
    Alias $slave encoding ::firewall::Invoke $slave encoding
}



package provide firewall $::firewall::version