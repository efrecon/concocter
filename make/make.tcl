#! /usr/bin/env tclsh

package require platform
package require http
package require tls

set tcllib_ver 1.18

set dirname [file dirname [file normalize [info script]]]
set kitdir [file join $dirname kits]
set bindir [file join $dirname bin]
set dstdir [file join $dirname distro]
set rootdir [file join $dirname ..]

::tcl::tm::path add [file join $rootdir lib toclbox]
package require toclbox;
toclbox verbosity * INFO

# Tcl 8.6.8, KitCreator 0.10.2, Platform linux-amd64-static, metakit, tcllib, tls, minimal build

# Quick options parsing, accepting several times -target
set targets [list]; set version ""; set force 0; set keep 0
for { set i 0 } { $i < [llength $argv] } { incr i } {
    set opt [lindex $argv $i]
    switch -glob -- $opt {
        "-t*" {
            incr i
            lappend targets [lindex $argv $i]
        }
        "-v*" {
            incr i
            set version [lindex $argv $i]
        }
        "-f*" {
            set force 1
        }
        "-k*" {
            set keep 1
        }
        "--" {
            incr i
            break
        }
        default {
            break
        }
    }
}
set argv [lrange $argv $i end]
if { ![llength $targets] } {
    set targets [list "concocter"]
}
toclbox log NOTICE "Building targets: $targets"

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


# Build for all platforms or specific platform
if { [llength $argv] == 0 } {
    set argv [dict keys [kits]]
}
toclbox log NOTICE "Building for platforms: $argv"

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

# Arrange for https to work properly
::http::register https 443 [list ::tls::socket -tls1 1]


# Protect wrapping through temporary directory
set origdir [pwd]
set wrapdir [file normalize [file join $origdir wrapper-[pid]-[expr {int(rand()*1000)}]]]
toclbox log NOTICE "Wrapping inside $wrapdir"
file mkdir $wrapdir
cd $wrapdir

proc cleanup { { target "" } } {
    if { $::keep } {
        toclbox log NOTICE "Keeping temporary files!"
        return
    }
    cd $::origdir

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

    
# Get the tcllib, this is a complete overkill, but is generic and
# might help us in the future.  We get it from the github mirror as
# the main fossil source is protected by a captcha.
if {0} {
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
    set xdir [lindex [glob -nocomplain -- *tcllib*$gver] 0]
    if { $xdir eq "" } {
        toclbox log ERROR "Could not find where tcllib was extracted!"
        cleanup
        exit
    }
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
        set kits [::kits]
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


foreach target $targets {
    # Decide upon the target, this covers ending .tcl extension (or not)
    set mainbin [file join $rootdir $target]
    if { ![file exists $mainbin] } {
        append mainbin .tcl
        if { ![file exists $mainbin] } {
            toclbox log ERROR "Nothing to wrap!"
            cleanup
            exit
        }
    }

    # Handle versioning for some of the targets
    if { $version eq "" && $target eq "concocter" } {
        # Run concocter and ask it for its current version number.
        toclbox log INFO "Getting version"
        set version [lindex [toclbox exec -return -- [info nameofexecutable] $mainbin -version] 0]
    }
    toclbox log NOTICE "Creating $target v$version"
    
    # Start creating an application directory structure using qwrap (from
    # sdx).
    toclbox log NOTICE "Creating skeleton and filling VFS"
    set tclkit [kit]
    if { $tclkit eq "" } {
        cleanup
        exit
    }
    set sdx [file join $kitdir sdx.kit]
    if { ![file exists $sdx] || $force } {
        if { [download $sdx https://chiselapp.com/user/aspect/repository/sdx/uv/sdx-20110317.kit] eq "" } {
            cleanup
            exit
        }
    }
    toclbox exec $tclkit $sdx qwrap $mainbin
    toclbox exec $tclkit $sdx unwrap ${target}.kit
    
    # Install application libraries into VFS    
    foreach fname [glob -directory [file join $rootdir lib] -nocomplain -- *] {
        set r_fname [file dirname [file normalize ${fname}/___]]
        toclbox log DEBUG "Copying $r_fname -> ${target}.vfs/lib"
        file copy -force -- $r_fname ${target}.vfs/lib
    }
    
    # And now, for each of the platforms requested at the command line,
    # build a platform dependent binary out of the kit.
    foreach platform $argv {
        set binkit [kit $platform]
        if { $binkit ne "" } {
            toclbox log INFO "Final wrapping of binary for $platform"
            toclbox exec $tclkit $sdx wrap ${target}.kit
            # Copy runtime to temporary because won't work if same as the
            # one we are starting from.
            set tmpkit [file join $wrapdir [file tail ${binkit}].temp]
            toclbox log DEBUG "Creating temporary kit for final wrapping: $tmpkit"
            file copy $binkit $tmpkit
            toclbox exec $tclkit $sdx wrap ${target} -runtime $tmpkit
            file delete -force -- $tmpkit
        } else {
            toclbox log ERROR "Cannot build for $platform, no main kit available"
        }
        
        # Move created binary to directory for official distributions
        if { $version eq "" } {
            set dstbin ${target}-$platform
        } else {
            set dstbin ${target}-$version-$platform            
        }
        if { [string match -nocase "win*" $platform] } {
            file rename -force -- ${target} [file join $dstdir $dstbin].exe
        } else {
            file rename -force -- ${target} [file join $dstdir $dstbin]
            file attributes [file join $dstdir $dstbin] -permissions a+x
        }
    }
    
    # Big cleanup
    if {! $keep} {
        file delete -force -- ${target}.vfs
        file delete -force -- ${target}.kit
        file delete -force -- ${target}.bat
    }
}

cleanup