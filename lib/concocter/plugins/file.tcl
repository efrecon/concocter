namespace eval ::concocter::var::plugin::file {
}

proc ::concocter::var::plugin::file::update { var location } {
    upvar \#0 $var VAR
    
    set updated 0
    set location [string trim [string range $VAR(-source) 1 end]]
    ::utils::debug DEBUG "Reading content of $VAR(-name) from $location"
    set fname [::utils::resolve $location]
    if { [catch {open $fname} fd] == 0 } {
        set updated [[namespace parent [namespace parent]]::setvar $var [read $fd]]
        close $fd
    } else {
        ::utils::debug ERROR "Cannot get value from $fname: $fd"                
    }
    
    return $updated
}