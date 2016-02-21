namespace eval ::concocter::var::plugin::mapper {
}

proc ::concocter::var::plugin::mapper::update { var xpr } {
    set value [string map [[namespace parent [namespace parent]]::snapshot] $xpr]
    return [[namespace parent [namespace parent]]::setvar $var $value]
}