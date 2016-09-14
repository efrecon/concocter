namespace eval ::concocter::var::plugin::file {
    namespace import [namespace parent [namespace parent]]::setvar
    namespace import [namespace parent [namespace parent]]::snapshot    
}

proc ::concocter::var::plugin::file::update { var location {resolution {}}} {
    upvar \#0 $var VAR
    
    set updated 0
    set location [string trim [string range $location 1 end]]
    set fname [::utils::resolve $location $resolution]
    if { $fname eq "" } {
        ::utils::debug WARN "Empty filename to read content of $VAR(-name) from!"
    } else {
        ::utils::debug DEBUG "Reading content of $VAR(-name) from $fname"
        if { [catch {open $fname} fd] == 0 } {
            set updated [setvar $var [read $fd]]
            close $fd
        } else {
            ::utils::debug ERROR "Cannot get value from $fname: $fd"                
        }
    }
    
    return $updated
}