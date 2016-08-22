namespace eval ::concocter::var::plugin::stats {
    namespace eval gvals {
    }
    namespace import [namespace parent [namespace parent]]::setvar
    namespace import [namespace parent [namespace parent]]::new
}

proc ::concocter::var::plugin::stats::update { var location } {
    variable gvals
    
    upvar \#0 $var VAR
    
    set updated 0
    set location [string trim [string range $location 1 end]]
    set location [::utils::resolve $location]
    ::utils::debug DEBUG "Getting statistics for $location"
    if { [catch {file stat $location stats} err] == 0 } {
        if { $stats(type) eq "directory" } {
            set stats(files) [glob -directory $location -nocomplain -tails -- *]
        }
        set updated [setvar $var [array get stats]]
    } else {
        ::utils::debug ERROR "Cannot get statistics for $location: $err"
    }
    return $updated
}