namespace eval ::concocter::output {
    variable version 0.1
    namespace eval output {};  # This will host all output information
    namespace eval gvars {
        variable generator 0;  # Generator for identifiers
    }
}


proc ::concocter::output::outputs {} {
    return [lsort [info vars [namespace current]::output::*]]
}

# ::output:update -- Update an output file
#
#       Update the file that it pointed out by an output specification using the
#       template specified. The file path to both the output file and the
#       template can be sugared using a number of %-surrounded strings.
#       Recognised are all environments variables, all elements of the platform
#       array, all the variables and the variables dirname, fname and rootname
#       (refering to where from the output specficiation was read, if relevant).
#
# Arguments:
#	out	Identifier of the output
#
# Results:
#       1 if the output was generated properly using the template.
#
# Side Effects:
#       None.
proc ::concocter::output::update { out } {
    upvar \#0 $out OUT
    
    # Construct a variable map for substitution of %-surrounded strings in
    # paths. 
    set varmap [[namespace parent]::var::snapshot * ""]
    if { $OUT(-context) ne ""} {
	lappend varmap \
	    dirname [file dirname $OUT(-context)] \
	    fname [file tail $OUT(-context)] \
	    rootname [file rootname [file tail $OUT(-context)]]
    }

    # Resolve path for this time (note that we use the content of variables,
    # which might be handy to automatically generate different filenames)
    set dst_path [::utils::resolve $OUT(-destination) $varmap]
    if { [string index $OUT(-template) 0] eq "@" } {
	set tpl_path [string trim [string range $OUT(-template) 1 end]]
	set tpl_path [::utils::resolve $tpl_path $varmap]
	::utils::debug INFO "Updating content of $dst_path using template at\
	                     $tpl_path"
    } else {
	set tpl_path ""
	::utils::debug INFO "Updating content of $dst_path using inline\
	                     template [[namespace parent]::clamp $OUT(-template)]"
    }
    
    # Create a template and execute it to output its result into the output file
    # path.
    set updated 0
    set tpl [::templater::new]
    if { $tpl_path eq "" } {
	::templater::parse $tpl $OUT(-template)
    } else {
	::templater::link $tpl $tpl_path	
    }
    foreach { k v } $varmap {
        ::templater::setvar $tpl $k $v
    }
    set res [::templater::render $tpl]
    if { [catch {open $dst_path w} fd] == 0 } {
        puts -nonewline $fd $res
        close $fd
        set updated 1
    } else {
        ::utils::debug ERROR "Cannot write to destination $dst_path"
    }
    ::templater::delete $tpl
    
    return $updated
}


proc ::concocter::output::new { dst tpl {context ""}} {
    variable gvars
    
    set out [namespace current]::output::[format %05d [incr gvars::generator]]
    upvar \#0 $out OUT
    set OUT(-destination) $dst
    set OUT(-template) $tpl
    set OUT(-context) $context
    
    return $out
}



package provide concocter::output $::concocter::output::version
