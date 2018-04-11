# This isn't properly packaged, just moved away the main script to clean things
# up.  Note, it also supposes access to a number of the global variables that
# are created in the main script, which is... ugh.. ugly...

proc ::kits {} {
    global bindir

    set kits [dict create]    
    set fd [open [file join $bindir bootstrap.dwl]]
    while {![eof $fd]} {
        set line [string trim [gets $fd]]
        if { $line ne "" && [string index $line 0] ne "\#" } {
            lassign $line platform url
            dict set kits $platform $url
        }
    }
    close $fd
    
    return $kits
}

# The missing procedure of the http package
proc ::http::geturl_followRedirects {url args} {
    while {1} {
        set token [eval [list http::geturl $url] $args]
        switch -glob -- [http::ncode $token] {
            30[1237] {
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


proc cleanup { { target "" } } {
    if { $::keep } {
        toclbox log NOTICE "Keeping temporary files!"
        return
    }
    cd $::wraproot

    set toremove [list]
    if { [info exists ::xdir] } { lappend toremove $::xdir }
    if { [info exists ::tcllib_path] } { lappend toremove $::tcllib_path }
    if { $target ne "" } {
        lappend toremove ${target}.vfs ${target}.kit
    }
    lappend toremove $::wrapdir

    foreach fname $toremove {
        if { [file exists $fname] } {
            file delete -force -- $fname
        }
    }
}


proc ::download { fpath url } {
    toclbox log NOTICE "Downloading $url to $fpath"
    
    set ret ""
    set tok [::http::geturl_followRedirects $url -binary on]
    if { [::http::ncode $tok] == 200 } {
        set fd [open $fpath "w"]
        fconfigure $fd -encoding binary -translation binary
        puts -nonewline $fd [::http::data $tok]
        close $fd
        set ret $fpath
    } else {
        toclbox log ERROR "Could not download from $url!"        
    }
    ::http::cleanup $tok
    return $ret
}


proc ::kit { { platform "" } } {
    global bindir force
    
    # Default platform to local
    if { $platform eq "" } {
        set platform [::platform::generic]
    }
    
    # Set extension for binaries (only on windows really)
    set ext ""
    if { [lindex [split $platform "-"] 0] eq "win32" } {
        set ext ".exe"
    }
    
    set tclkit [file join $bindir $platform tclkit${ext}]
    if { ![file exists $tclkit] || $force } {
        set kits [kits]
        if { [dict exists $kits $platform] } {
            set url [dict get $kits $platform]
            toclbox log NOTICE "Downloading tclkit for $platform from $url"
            file mkdir [file dirname $tclkit]
            if { [::download $tclkit $url] eq "" } {
                return ""
            }
            if { [lindex [split $platform "-"] 0] ne "win32" } {
                file attributes $tclkit -permissions a+x
            }
        }
    }
    return $tclkit
}


# Get the tcllib, this is a complete overkill, but is generic and
# might help us in the future. We get it from the github mirror as
# the main fossil source is protected by a captcha.
proc ::get_tcllib { {tcllib_ver ""} } {
    # Default to global version
    if { $tcllib_ver eq "" } { set tcllib_ver $::tcllib_ver }
    toclbox log NOTICE "Getting tcllib v$tcllib_ver from github mirror"
    set gver [string map [list . _] $tcllib_ver]
    set url https://github.com/tcltk/tcllib/archive/tcllib_$gver.tar.gz
    set tcllib_path tcllib-[pid]-[expr {int(rand()*1000)}].tar.gz
    if { [download $tcllib_path $url] eq "" } {
        cleanup
        exit
    }
    
    # Extract the content of tcllib to disk for a while
    toclbox log NOTICE "Extracting tcllib"
    toclbox exec -- tar zxf $tcllib_path
    set ::xdir [lindex [glob -nocomplain -- *tcllib*$gver] 0]
    if { $::xdir eq "" } {
        toclbox log ERROR "Could not find where tcllib was extracted!"
        cleanup
        exit
    }
}
