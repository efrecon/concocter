namespace eval ::concocter::var::plugin::mapper {
    namespace import [namespace parent [namespace parent]]::setvar
}

proc ::concocter::var::plugin::mapper::update { var xpr } {
    return [setvar $var $xpr]
}