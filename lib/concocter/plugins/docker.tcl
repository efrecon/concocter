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
    set location [string trim [string range $location 1 end]]
    set location [::utils::resolve $location]
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
        set raw [$daemon containers]
        foreach cspec $raw {
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

            # Get network information
            foreach {ip mac} [Network [dict get $cspec Id] $raw] break
            set v [new $VAR(-name)-${cid}-ip]
            set updated [expr $updated||[setvar $v $ip]]
            set v [new $VAR(-name)-${cid}-mac]
            set updated [expr $updated||[setvar $v $mac]]                

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
            # environment variables and labels. For each variable, declare and
            # set, prepending the name of the main variable and the (short)
            # identifier of the container.
            set details [$daemon inspect [dict get $cspec Id]]
            set config [dict get $details Config]

            # Environment vars, encapsulate under -environment in namespace
            set e_vars [list]
            foreach env [dict get $config Env] {
                set idx [string first "=" $env]
                if { $idx > 0 } {
                    set e_var [string range $env 0 [expr {$idx-1}]]
                    set e_val [string range $env [expr {$idx+1}] end]                    
                    set v [new $VAR(-name)-${cid}-environment-$e_var]
                    set updated [expr $updated||[setvar $v $e_val]]
                    lappend e_vars $e_var
                }
            }

            # Make sure we also set a variable that contains the list of all
            # environment variables to ease looping in templates.
            set v [new $VAR(-name)-${cid}-environment]
            set updated [expr $updated||[setvar $v $e_vars]]

            # Environment vars, encapsulate under -label in namespace
            set labels [list]
            foreach {lbl val} [dict get $config Labels] {
                set v [new $VAR(-name)-${cid}-label-$lbl]
                set updated [expr $updated||[setvar $v $val]]
                lappend labels $lbl
            }
            
            # Make sure we also set a variable that contains the list of all
            # environment variables to ease looping in templates.
            set v [new $VAR(-name)-${cid}-label]
            set updated [expr $updated||[setvar $v $labels]]
        }
        
        # Finally set the main variable to be the list of currently running and
        # known containers.
        set v [new $VAR(-name)]
        set updated [expr $updated||[setvar $v $containers]]
        
        $daemon disconnect
    }
    
    return $updated
}


proc ::concocter::var::plugin::docker::Network { cid raw } {
    set ip ""
    set mac ""
    foreach cspec $raw {
        if { [dict get $cspec Id] eq $cid } {
            # This only covers the netmode "default" (i.e. bridge) and when
            # using the network of another container. We should cover all the
            # other cases, incl. host network.
            set networks [dict get $cspec NetworkSettings Networks]
            set netmode [dict get $cspec HostConfig NetworkMode]
            if { [dict exists $networks bridge] } {
                set ip [dict get $networks bridge IPAddress]
                set mac [dict get $networks bridge MacAddress]                
            } elseif { [string match container:* $netmode] } {
                foreach {x other} [split $netmode ":"] break
                return [Network $other $raw]
            } else {
            }            
        }
    }
    
    return [list $ip $mac]
}