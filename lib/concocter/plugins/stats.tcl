namespace eval ::concocter::var::plugin::stats {
    namespace eval gvars {
    }
    namespace import [namespace parent [namespace parent]]::setvar
    namespace import [namespace parent [namespace parent]]::snapshot    
}

proc ::concocter::var::plugin::stats::update { var location {resolution {}}} {
    variable gvals
    
    upvar \#0 $var VAR
    
    set updated 0
    set location [string trim [string range $location 1 end]]
    set location [::utils::resolve $location $resolution]
    if { $location eq "" } {
        ::utils::debug WARN "Empty location to collect statistics into $VAR(-name)!"
    } else {
        ::utils::debug DEBUG "Getting statistics for $location into $VAR(-name)"
        if { [catch {file stat $location stats} err] == 0 } {
            if { $stats(type) eq "directory" } {
                set stats(files) [glob -directory $location -nocomplain -tails -- *]
            }
            set updated [setvar $var [array get stats]]
        } else {
            ::utils::debug ERROR "Cannot get statistics for $location: $err"
        }
    }
    return $updated
}