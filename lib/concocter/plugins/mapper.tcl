namespace eval ::concocter::var::plugin::mapper {
    namespace import [namespace parent [namespace parent]]::setvar
    namespace import [namespace parent [namespace parent]]::snapshot    
}

proc ::concocter::var::plugin::mapper::update { var xpr } {
    set value [string map [snapshot] $xpr]
    return [setvar $var $value]
}