namespace eval ::concocter::var::plugin::exec {
    namespace eval gvars {
    }
    namespace import [namespace parent [namespace parent]]::setvar
    namespace import [namespace parent [namespace parent]]::snapshot    
}

# Execute the location as an external command. There is currently no protection
# against malicious usage.
proc ::concocter::var::plugin::exec::update { var location {resolution {}} } {
    variable gvals
    
    upvar \#0 $var VAR
    
    set updated 0
    set location [string trim [string range $location 1 end]]
    set location [::utils::resolve $location $resolution]
    if { $location eq "" } {
        ::utils::debug WARN "Nothing to execute to update content of $VAR(-name)"
    } else {
        ::utils::debug DEBUG "Executing $location to update content of $VAR(-name)"
        if { [catch {eval exec -- $location} res] == 0 } {
            set updated [setvar $var $res]
        } else {
            ::utils::debug ERROR "Cannot execute $location: $res"
        }
    }
    return $updated
}