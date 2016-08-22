namespace eval ::concocter::var::plugin::exec {
    namespace eval gvals {
    }
    namespace import [namespace parent [namespace parent]]::setvar
}

# Execute the location as an external command. There is currently no protection
# against malicious usage.
proc ::concocter::var::plugin::exec::update { var location } {
    variable gvals
    
    upvar \#0 $var VAR
    
    set updated 0
    set location [string trim [string range $location 1 end]]
    set location [::utils::resolve $location]
    ::utils::debug DEBUG "Executing $location"
    if { [catch {eval exec -- $location} res] == 0 } {
        set updated [setvar $var $res]
    } else {
        ::utils::debug ERROR "Cannot execute $location: $res"
    }
    return $updated
}