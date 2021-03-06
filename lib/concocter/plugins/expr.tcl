namespace eval ::concocter::var::plugin::expr {
    namespace import [namespace parent [namespace parent]]::setvar
}

proc ::concocter::var::plugin::expr::update { var xpr {resolution {}}} {
    upvar \#0 $var VAR
    
    set updated 0
    # Math expression, there is no protection against cyclic
    # dependencies or order.
    set xpr [string trim [string range $xpr 1 end]]
    if { [catch {expr $xpr} value] == 0 } {
        set updated [setvar $var $value]
    } else {
        ::utils::debug ERROR "Cannot evaluate math. expression $VAR(-source): $value"
    }
    
    return $updated
}