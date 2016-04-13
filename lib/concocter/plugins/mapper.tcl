namespace eval ::concocter::var::plugin::mapper {
    namespace import [namespace parent [namespace parent]]::setvar
    namespace import [namespace parent [namespace parent]]::snapshot
}

# Mapper is able to pick up not only the content of existing variables which
# name is enclosed by %, but also environment variables, the one from the
# tcl_platform array and supports defaulting value when the variable does not
# exist.
proc ::concocter::var::plugin::mapper::update { var xpr } {
    return [setvar $var [::utils::resolve $xpr [snapshot * ""]]]
}