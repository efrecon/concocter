namespace eval ::concocter::var {
    variable version 0.1
    namespace eval var {};     # This will host all variable information
    namespace eval plugin {};  # Namespace reserved for plugins
    namespace eval gvars {
        variable generator 0;  # Generator for identifiers
        variable plugins {};   # List of registered plugins
    }
    
    variable libdir [file dirname [file normalize [file dirname [info script]/___]]]
    
    namespace export {[a-z]*}
}


proc ::concocter::var::vars {} {
    return [lsort [info vars [namespace current]::var::*]]    
}


proc ::concocter::var::find { name } {
    foreach v [vars] {
        upvar \#0 $v VAR
        if { $name eq $VAR(-name) } {
            return $v
        }
    }
    return ""
}


# ::var:snapshot -- Variable snapshot
#
#       Return a snapshot of the current variables and their values. The
#       snapshot is an even-long list, where the variable names are surrounded
#       by the escape character string.
#
# Arguments:
#	names	Consider only variables which name matches this pattern
#	escape	Escape string to surround each variable name with
#
# Results:
#       An even-long list respresenting the snapshot of all matching variables.
#
# Side Effects:
#       None.
proc ::concocter::var::snapshot { {names *} {escape %}} {
    set mapper [list]
    foreach v [vars] {
	upvar \#0 $v VAR
	if { [string match $names $VAR(-name)] } {
	    lappend mapper ${escape}$VAR(-name)${escape} $VAR(value)
	}
    }
    return $mapper
}


proc ::concocter::var::setvar { var value } {
    upvar \#0 $var VAR

    set VAR(previous) $VAR(value)
    set VAR(value) $value
    set updated [expr {$VAR(value) ne $VAR(previous)}]
    if { $updated } {
        ::utils::debug DEBUG "Updated variable $VAR(-name) to '[[namespace parent]::clamp $VAR(value)]'"
    }
    return $updated
}


# ::var:update -- Update the value of a variable
#
#       Update the value of a variable, depending on its source. When the source
#       starts with a "@" sign, the URL location (or a file) is fetched and its
#       content will be the value of the variable. Otherwise, this should be a
#       mathematical expression, which can depend on the value of other
#       variables. In that expression, the names of other variables should be
#       surrounded by the "%" sign.
#
# Arguments:
#	var	Identifier of the variable.
#
# Results:
#       1 if the content of the variable has changed and was updated, 0
#       otherwise.
#
# Side Effects:
#       None.
proc ::concocter::var::update { var } {
    variable gvars

    upvar \#0 $var VAR

    foreach {ptn cmd} $gvars::plugins {
        if { $VAR(-source) ne "" && [string match $ptn $VAR(-source)] } {
            set src [string map [snapshot] $VAR(-source)]
            # Let it fail and propagate error to caller on purpose
            return [eval [list $cmd $var $src [Hints $VAR(-origin)]]]
        }
    }
    return 0
}


proc ::concocter::var::Hints { path } {
    
    if { $path eq "" } {
        return [dict create dir "" dirname "" rootname ""]
    }
    return [dict create \
                dir [file dirname $path] \
                dirname [file dirname $path] \
                rootname [file rootname [file tail $path]]]
}


proc ::concocter::var::plugin { ptn path } {
    variable libdir
    variable gvars
    
    set path [::utils::resolve $path [list libdir $libdir]]
    if { [catch {source $path} res] == 0 } {
        set entry [file tail [file rootname $path]]
        set updCmd [namespace current]::plugin::${entry}::update
        if { [llength [info commands $updCmd]] > 0 } {
            lappend gvars::plugins $ptn $updCmd
            ::utils::debug INFO "Registered plugin for $ptn at $updCmd"
        }
    } else {
        ::utils::debug ERROR "Cannot load plugin at $path: $res"
    }
}


proc ::concocter::var::new { name { src "" } {dft ""} {origin ""}} {
    variable gvars
    
    set var [find $name]
    if { $var eq "" } {
        set var [namespace current]::var::[format %05d [incr gvars::generator]]
        upvar \#0 $var VAR
        set VAR(-name) $name
        set VAR(-source) $src
        set VAR(-origin) $origin
        set VAR(value) $dft
        if { $src eq "" } {
            ::utils::debug DEBUG "Created internal variable $name (default: $dft)"    
        } else {
            ::utils::debug DEBUG "Created variable $name to update from $src (default: $dft)"    
        }
    } else {
        if { $src ne "" } {
            return -code error "Cannot change source of existing variable to $src"
        } elseif { $dft ne "" } {
            setvar $var $dft
            ::utils::debug DEBUG "Silently updated variable $name to $dft"
        }
    }
    
    return $var
}




package provide concocter::var $::concocter::var::version
