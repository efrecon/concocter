package require docker

namespace eval ::concocter::var::plugin::docker {
    namespace eval gvals {
        variable -truncate    11
    }
    namespace import [namespace parent [namespace parent]]::setvar
    namespace import [namespace parent [namespace parent]]::new
}

proc ::concocter::var::plugin::docker::update { var location } {
    variable gvals
    
    upvar \#0 $var VAR
    
    set updated 0
    set location [string trim [string range $VAR(-source) 1 end]]
    set idx [string first "docker+" $location]
    if { $idx >= 0 } {
        incr idx [string length "docker+"]
        set location [string range $location $idx end]
        ::utils::debug DEBUG "Filling namespace starting at $VAR(-name) using $location"
        set daemon [docker connect $location]
        
        # Use the name of the variable as a namespace, i.e. automatically create
        # a set of variables (see below) using this variable name as prefix and
        # describing the current content of all containers at the docker daemon.
        set containers [list]
        foreach cspec [$daemon containers] {
            # Truncate the full name to the first 12 characters as docker itself
            # uses to. This will keep the names of the variables to some decent
            # size... We will create, below, a large number of variables which
            # names are formed as follows: the name of the main variable,
            # followed by a dash, followed by the (short) container identifier,
            # followed by a dash, followed by a key specifying the variable
            # (name, id, ports, etc.).
            set cid [string range [dict get $cspec Id] 0 ${gvals::-truncate}]
            lappend containers $cid
            
            # Make sure we set the complete ID anyway
            set v [new $VAR(-name)-${cid}-id]
            set updated [expr $updated||[setvar $v [dict get $cspec Id]]]

            # Get the first name, cleaned away from leading slash
            set cname [lindex [dict get $cspec Names] 0]
            set v [new $VAR(-name)-${cid}-name]
            set updated [expr $updated||[setvar $v [string trimleft $cname /]]]

            # Get network information when we have a bridge, we ought to have a
            # solution for the other types of networks.
            set networks [dict get $cspec NetworkSettings Networks]
            if { [dict exists $networks bridge] } {
                set v [new $VAR(-name)-${cid}-ip]
                set updated [expr $updated||[setvar $v [dict get $networks bridge IPAddress]]]
                set v [new $VAR(-name)-${cid}-mac]
                set updated [expr $updated||[setvar $v [dict get $networks bridge MacAddress]]]                
            } else {
                set v [new $VAR(-name)-${cid}-ip]
                set v [new $VAR(-name)-${cid}-mac]
            }

            # Create a list of the external ports, add the type of the port
            # after a slash.
            set ports [list]
            foreach pspec [dict get $cspec Ports] {
                if { [dict exists $pspec PublicPort] } {
                    lappend ports [dict get $pspec PublicPort]/[dict get $pspec Type]
                }
            }
            set v [new $VAR(-name)-${cid}-ports]
            set updated [expr $updated||[setvar $v $ports]]

            # Which image is the container coming from.
            set v [new $VAR(-name)-${cid}-image]
            set updated [expr $updated||[setvar $v [dict get $cspec Image]]]
            
            # Now inspect fully the container to be able to access the
            # environment variables. For each variable, declare and set,
            # prepending the name of the main variable and the (short)
            # identifier of the container.
            set details [$daemon inspect [dict get $cspec Id]]
            set config [dict get $details Config]
            set e_vars [list]
            foreach env [dict get $config Env] {
                set idx [string first "=" $env]
                if { $idx > 0 } {
                    set e_var [string range $env 0 [expr {$idx-1}]]
                    set e_val [string range $env [expr {$idx+1}] end]
                    set v [new $VAR(-name)-${cid}-$e_var]
                    set updated [expr $updated||[setvar $v $e_val]]
                    lappend e_vars $e_var
                }
            }
            
            # Make sure we also set a variable that contains the list of all
            # environment variables to ease looping in templates.
            set v [new $VAR(-name)-${cid}-environment]
            set updated [expr $updated||[setvar $v $e_vars]]
        }
        
        # Finally set the main variable to be the list of currently running and
        # known containers.
        set v [new $VAR(-name)]
        set updated [expr $updated||[setvar $v $containers]]
        
        $daemon disconnect
    }
    
    return $updated
}