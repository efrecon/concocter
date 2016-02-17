package require Tcl 8.4

package require utils

namespace eval ::templater {
    variable TPL

    if {![info exists TPL]} {
	array set TPL {
	    -var          "__r_e_s_u_l_t__"
	    -munge        on
	    -sourceCmd    ""
	}
	variable libdir [file dirname [file normalize [info script]]]
	variable version 0.2
    }
}

proc ::templater::__source { t fname } {
    variable TPL
    upvar \#0 $t TEMPLATE

    if { $TEMPLATE(-sourceCmd) eq "" } {
	::utils::debug 3 "Sourcing of external script $fname is forbidden\
                          unless you explicitely provide a callback"
    } else {
	if { [catch {eval [linsert $TEMPLATE(-sourceCmd) end \
			       $t $fname]} res] == 0 } {
	    if { $res ne "" } {
		if { [catch {$TEMPLATE(interp) eval $res} err] } {
		    ::utils::debug 3 "Sourcing of $fname failed: $err"
		}
	    }
	} else {
	    ::utils::debug 3 "Inlining of $fname failed: $res"
	}
    }
}


proc ::templater::__puts { args } {
    ::utils::debug 5 [lindex $args end]
}


proc ::templater::__append { t code_ out } {
    upvar $code_ code
    upvar \#0 $t TEMPLATE

    if { [string is true $TEMPLATE(-munge)] } {
	if { [string trim $out] ne "" || [string index $out end] ne "\n" } {
	    append code "append $TEMPLATE(-var) [list $out]\n"
	}
    } else {
	append code "append $TEMPLATE(-var) [list $out]\n"
    }
}

proc ::templater::__transcode { t txt } {
    variable TPL

    upvar \#0 $t TEMPLATE
    
    set code "set $TEMPLATE(-var) {}\n"
    while {[set i [string first <% $txt]] != -1} {
	incr i -1
	__append $t code [string range $txt 0 $i]
	set txt [string range $txt [expr {$i + 3}] end]
	if {[string index $txt 0] eq "="} {
	    append code "append $TEMPLATE(-var) "
	    set txt [string range $txt 1 end]
	}
	if {[set i [string first %> $txt]] == -1} {
	    return -code error "No matching %> when parsing\
                                '[string range $txt 0 15]...'"
	}
	incr i -1
	append code "[string range $txt 0 $i] \n"
	set txt [string range $txt [expr {$i + 3}] end]
    }
    if {$txt ne ""} { __append $t code $txt }
    append code "set $TEMPLATE(-var)"

    return $code
}



proc ::templater::__init { t { force off } } {
    variable TPL

    upvar \#0 $t TEMPLATE
    
    if { $TEMPLATE(interp) eq "" } {
	set TEMPLATE(interp) [interp create -safe]
	$TEMPLATE(interp) alias puts ::templater::__puts
	$TEMPLATE(interp) alias source ::templater::__source $t
	set TEMPLATE(initvars) [$TEMPLATE(interp) eval info vars]
    }

    if { [string is true $force] } {
	set vars [$TEMPLATE(interp) eval info vars]
	foreach v $vars {
	    if { [lsearch $TEMPLATE(initvars) $v] < 0 } {
		$TEMPLATE(interp) eval unset $v
	    }
	}
	set TEMPLATE(code) ""
    }
    
    return $TEMPLATE(interp)
}


proc ::templater::alias { t src tgt args } {
    variable TPL

    upvar \#0 $t TEMPLATE
    
    if { $TEMPLATE(interp) ne "" } {
	return [eval $TEMPLATE(interp) alias $src $tgt $args]
    }
}


proc ::templater::setvar { t var value } {
    variable TPL

    upvar \#0 $t TEMPLATE
    ::utils::debug 5 "Setting $var to be $value"
    $TEMPLATE(interp) eval [list set $var $value]
}


proc ::templater::getvar { t var } {
    variable TPL

    upvar \#0 $t TEMPLATE
    return [$TEMPLATE(interp) eval [list set $var]]
}


proc ::templater::render { t } {
    variable TPL

    upvar \#0 $t TEMPLATE

    set txt ""
    if { $TEMPLATE(fname) ne "" } {
	if { [file mtime $TEMPLATE(fname)] != $TEMPLATE(mtime) } {
	    ::utils::debug 3 "Linked file $TEMPLATE(fname) modified,\
                              reading again its content"
	    __linkfile $t $TEMPLATE(fname)
	}
    }

    if { $TEMPLATE(code) ne "" } {
	if { [catch {$TEMPLATE(interp) eval $TEMPLATE(code)} txt] } {
	    ::utils::debug 1 "Could not interpret templating code. Error: $txt\
                              when executing\n$TEMPLATE(code)"
	    set txt ""
	} else {
	    ::utils::debug 5 "Properly executed templating code in safe interp"
	}
    }
    return $txt
}


proc ::templater::parse { t txt } {
    variable TPL

    upvar \#0 $t TEMPLATE

    set TEMPLATE(code) ""
    if { [catch {__transcode $t $txt} code] } {
	::utils::debug 3 "Parsing error: $code"
    } else {
	set TEMPLATE(code) $code
        ::utils::debug 5 "Successfully parsed template text"
    }

    return [expr {$TEMPLATE(code) ne ""}]
}


proc ::templater::__linkfile { t fname } {
    variable TPL

    upvar \#0 $t TEMPLATE
    ::utils::debug 4 "Reading content of $fname into template"
    if { [catch {open $fname} fd] } {
	::utils::debug 1 "Could not open $fname for reading: $fd"
	return
    }
    set txt [read $fd]
    close $fd

    if { [parse $t $txt] } {
	set TEMPLATE(fname) $fname
	set TEMPLATE(mtime) [file mtime $fname]
    }
}


proc ::templater::link { t { fname "" } } {
    variable TPL

    upvar \#0 $t TEMPLATE

    if { $fname ne "" } {
	if { $TEMPLATE(fname) eq "" } {
	    __linkfile $t $fname
	} elseif { $TEMPLATE(fname) ne $fname } {
	    __linkfile $t $fname
	}
    }

    return $TEMPLATE(fname)
}


proc ::templater::unlink { t } {
    variable TPL

    upvar \#0 $t TEMPLATE

    ::utils::debug 4 "Unlinking previously linked file $TEMPLATE(fname)"
    set TEMPLATE(fname) ""
    set TEMPLATE(mtime) ""
}


proc ::templater::reset { t } {
    __init $t on
}


proc ::templater::delete { t } {
    variable TPL

    upvar \#0 $t TEMPLATE

    if { $TEMPLATE(interp) ne "" } {
	interp delete $TEMPLATE(interp)
    }
    unset $t
}


proc ::templater::config { t args } {
    variable TPL

    upvar \#0 $t TEMPLATE
    
    foreach k [array names TPL -*] {
	::utils::getopt args $k TEMPLATE($k) $TEMPLATE($k)
    }
    __init $t
}


proc ::templater::new { args } {
    variable TPL

    set t [::utils::identifier [namespace current]::template:]
    upvar \#0 $t TEMPLATE

    set TEMPLATE(interp) ""
    set TEMPLATE(code) ""
    set TEMPLATE(initvars) [list]
    set TEMPLATE(fname) ""
    set TEMPLATE(mtime) ""
    
    foreach k [array names TPL -*] {
	::utils::getopt args $k TEMPLATE($k) $TPL($k)
    }

    eval config $t $args
    return $t
}

package provide templater $::templater::version