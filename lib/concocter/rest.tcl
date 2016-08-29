namespace eval ::concocter::rest {
    variable version 0.1
    namespace eval gvars {
        variable servers {};   # List of web servers we implement
    }
    namespace eval var {
        namespace import [namespace parent [namespace parent]]::var::*
    }
}


proc ::concocter::rest::server { port { www "" } } {
    variable gvars
    
    set srv [::minihttpd::new $www $port]
    if { $srv < 0 } {
	::utils::debug WARN "Cannot start web server on port $port"
	return $srv
    }
    
    ::minihttpd::handler $srv /var/get/* [namespace current]::Get "text/plain"
    ::minihttpd::handler $srv /var/get [namespace current]::Get "text/plain"
    ::minihttpd::handler $srv /var/set/* [namespace current]::Set "text/plain"
    ::minihttpd::handler $srv /var/new/* [namespace current]::New "text/plain"
    ::minihttpd::handler $srv /reload [namespace current]::Reload "text/plain"
    
    lappend gvars::servers $srv
    return $srv
}


proc ::concocter::rest::Get { prt sock url qry } {
    # Extract name of variable from last element of URL path
    set vname [lindex [split $url /] end]

    if { $vname eq "get" } {
        set vars [list]
        foreach v [var::vars] {
            upvar #0 $v V
            lappend vars $V(-name)
        }
        return $vars
    } else {
        set v [var::find $vname]
        if { $v ne "" } {
            upvar #0 $v V
            return $V(value)
        }
    }
    return ""    
}


proc ::concocter::rest::Set { prt sock url qry } {
    # Extract name of variable from last element of URL path
    set vname [lindex [split $url /] end]

    set updated 0
    set v [var::find $vname]
    if { $v ne "" } {
        set updated [var::setvar $v [::minihttpd::data $prt $sock]]
    }
    
    # Should we introduce some reloading delay to avoid regenerating the
    # templates on and on when doing multiple set?
    if { $updated } {
        [namespace parent]::reload
    }
    
    return $updated
}


proc ::concocter::rest::Reload { prt sock url qry } {
    [namespace parent]::reload
}


package provide concocter::rest $::concocter::rest::version
