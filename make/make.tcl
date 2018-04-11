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

foreach module [list "makelib"] {
    set fpath [file join $dirname lib ${module}.tcl]
    toclbox log DEBUG "Loading module $module from $fpath"
    source $fpath
}

# Quick options parsing, accepting several times -target
set targets [list];  # Empty will be all known targets, only concocter at this time.
set version "";      # Empty means as the target for its version
set force 0;         # Force (re)fetching of relevant binaries (tclkits, sdx, etc.)
set keep 0;          # Keep temporary files for debugging
set wraproot [pwd];  # Which directory in which to create the wrapping directory
set verbosity INFO;  # Verbosity level
for { set i 0 } { $i < [llength $argv] } { incr i } {
    set opt [lindex $argv $i]
    switch -glob -- $opt {
        "-t*" {
            # -targets, list of things to make, i.e. just concoter right now
            incr i
            lappend targets [lindex $argv $i]
        }
        "-v*" {
            # -version, force a version number, will default to the one reported
            # by concocter when running.
            incr i
            set version [lindex $argv $i]
        }
        "-f*" {
            # -force (re)fetching of binaries
            set force 1
        }
        "-k*" {
            # -keep temporary files (this is only for debugging)
            set keep 1
        }
        "-p*" {
            # -platforms list all available platforms and exit.
            puts "Available platforms: [join [dict keys [::kits]] ,\ ]"
            exit
        }
        "-w*" {
            # -wrapper path to directory in which to make wrapper directory.
            incr i
            set wraproot [lindex $argv $i]
        }
        "-v*" {
            # -verbosity Verbosity for output, something supported by toclbox.
            incr i
            toclbox verbosity * [lindex $argv $i]
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

# Build for all platforms or specific platform
if { [llength $argv] == 0 } {
    set argv [dict keys [kits]]
}
toclbox log NOTICE "Building for platforms: $argv"

# Arrange for https to work properly
toclbox https

# Protect wrapping through temporary directory
set wrapdir [file normalize [file join $wraproot wrapper-[pid]-[expr {int(rand()*1000)}]]]
toclbox log NOTICE "Wrapping inside $wrapdir"
file mkdir $wrapdir
cd $wrapdir

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
    toclbox log INFO "Creating skeleton and filling VFS"
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