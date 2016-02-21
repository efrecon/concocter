package require base64

namespace eval ::concocter::var::plugin::http {
    
}

# ::http::geturl_followRedirects -- geturl++
#
#       This procedure behaves exactly as the standard ::http::geturl, except
#       that it automatically follows refirects. It will follow redirects for a
#       finite number of times in order to always end.
#
# Arguments:
#	url	URL to get
#	args	Arguments to geturl
#
# Results:
#       HTTP token of the last URL that was got.
#
# Side Effects:
#       None.
proc ::concocter::var::plugin::http::GetURL {url args} {
    for { set i 0 } { $i<20 } { incr i} {
        set token [eval [list ::http::geturl $url] $args]
        switch -glob -- [::http::ncode $token] {
            30[1237] {
                if {[catch {array set OPTS $args}]==0} {
                    if { [info exists OPTS(-channel)] } {
                        seek $OPTS(-channel) 0 start
                    }
                }
            }
            default  { return $token }
        }
        upvar #0 $token state
        array set meta [set ${token}(meta)]
        if {![info exist meta(Location)]} {
            return $token
        }
        set url $meta(Location)
        unset meta
    }
}


proc ::concocter::var::plugin::http::update { var location } {
    upvar \#0 $var VAR
    
    set updated 0
    set location [string trim [string range $VAR(-source) 1 end]]
    ::utils::debug DEBUG "Reading content of $VAR(-name) from $location"
    array set URI [::uri::split $location]
    set hdrs [list]
    if { [info exists URI(user)] && $URI(user) ne "" } {
        lappend hdrs Authorization "Basic [base64::encode $URI(user):$URI(pwd)]"
    }
    set tok [[namespace parent]::GetURL $location -headers $hdrs]
    if { [::http::ncode $tok] >= 200 && [::http::ncode $tok] < 300 } {
        set updated [[namespace parent [namespace parent]]::setvar $var [::http::data $tok]]
    } else {
        ::utils::debug ERROR "Cannot get value from $location"
    }
    ::http::cleanup $tok
    
    return $updated
}