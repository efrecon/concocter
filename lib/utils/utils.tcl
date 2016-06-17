package require Tcl 8.5;

namespace eval ::utils {
    variable UTILS
    if {![info exists UTILS] } {
	array set UTILS {
	    idGene         0
	    idClamp        10000
	    idFormat       7
	    verbose        {* 5}
	    dbgfd          stderr
	    dateLogHeader  "\[%Y%m%d %H%M%S\] \[%pkg%\] "
	    comments       "\#"
	    verboseTags    {1 CRITICAL 2 ERROR 3 WARN 4 NOTICE 5 INFO 6 DEBUG 7 TRACE}
	    subst          {% @ ~}
	    dflt_sep       {/ |}
	    empty          {\"\" \{\} -}
	    fullpath       ""
	    maxresolve     10
	}
	
	variable version 0.1
    }
}


# ::utils::UpVar -- Find true caller
#
#       Finds how many stack levels there are between the direct
#       caller to this procedure and the true caller of that caller,
#       accounting for indirection procedures aiming at making
#       available some of the local procedures from this namespace to
#       child namespaces.
#
# Arguments:
#	None.
#
# Results:
#       Number of levels to jump up the stack to access variables as
#       if upvar 1 had been used in regular cases.
#
# Side Effects:
#       None.
proc ::utils::UpVar {} {
    set signature [info level -1]
    for { set caller -1} { $caller>-10 } { incr caller -1} {
	if { [info level $caller] eq $signature } {
	    return [expr {-$caller}]
	}
    }
    return 1
}


# ::utils::getopt -- Quick options parser
#
#       Parses options (and their possible) values from an option list. The
#       parser provides full introspection. The parser accepts itself a number
#       of dash-led options, which are:
#	-value   Which variable to store the value given to the option in.
#	-option  Which variable to store which option (complete) was parsed.
#	-default Default value to give when option not present.
#
# Arguments:
#	_argv	Name of option list in caller's context
#	name	Name of option to extract (first match, can be incomplete)
#	args	Additional arguments
#
# Results:
#       Returns 1 when a matching option was found and parsed away from the
#       option list, 0 otherwise
#
# Side Effects:
#       Modifies the option list to enable being run in loops.
proc ::utils::getopt {_argv name args } {
    # Get options to the option parsing procedure...
    array set OPTS {
	-value  ""
	-option ""
    }
    array set OPTS $args
    
    # Access where the options are stored and possible where to store
    # side-results.
    upvar [UpVar] $_argv argv
    if { $OPTS(-value) ne "" } {
	upvar [UpVar] $OPTS(-value) var
    }
    if { $OPTS(-option) ne "" } {
	upvar [UpVar] $OPTS(-option) opt
    }
    set opt "";  # Default is no option was extracted
    set pos [lsearch -regexp $argv ^$name]
    if {$pos>=0} {
	set to $pos
	set opt [lindex $argv $pos];  # Store the option we extracted
	# Pick the value to the option, if relevant
	if {$OPTS(-value) ne ""} {
	    set var [lindex $argv [incr to]]
	}
	# Remove option (and possibly its value from list)
	set argv [lreplace $argv $pos $to]
	return 1
    } else {
	# Did we provide a value to default?
	if { [info exists OPTS(-default)] } {
	    set var $OPTS(-default)
	}
	return 0
    }
}



proc ::utils::pullopt {_argv _opts} {
    upvar [UpVar] $_argv argv $_opts opts

    set opts {}
    set ddash [lsearch $argv "--"]
    if { $ddash >= 0 } {
	# Double dash is always on the safe-side.
	set opts [lrange $argv 0 [expr {$ddash-1}]]
	set argv [lrange $argv [expr {$ddash+1}] end]
    } else {
	# Otherwise, we give it a good guess, i.e. first non-dash-led
	# argument is the start of the arguments.
	for {set i 0} {$i < [llength $argv]} {incr i 2} {
	    if { [string index [lindex $argv $i] 0] ne "-" } {
		set opts [lrange $argv 0 [expr {$i-1}]]
		set argv [lrange $argv $i end]
		break
	    }
	}
	if { $i >= [llength $argv] } {
	    set opts $argv
	    set argv {}
	}
    }
}


# ::utils::pushopt -- Option parsing with insertion/appending
#
#       The base function of this procedure is to extract an option
#       from a list of arguments and pushes its value into an array.
#       However, the procedure recognises the special characters < and
#       > at the end of the option names.  These are respectively
#       understood as prepending or appending the content extracted
#       from the arguments to the CURRENT content of the option in the
#       array.  This will typically be used to append or prepend
#       specific details to "good" defaults, instead or rewriting them
#       all.
#
# Arguments:
#	_argv	Pointer to list of arguments
#	opt	Base option to get from arguments (sans trailing < or >)
#	_ary	Destination array.
#
# Results:
#       None.
#
# Side Effects:
#       Modifies the content of the array.
proc ::utils::pushopt { _argv opt _ary } {
    upvar $_argv argv $_ary ARY
    set modified [list]
    
    while { [getopt argv $opt -value val -option extracted] } {
	if { [string index $extracted end] eq "<" } {
	    set ARY($opt) $val\ $ARY($opt)
	    ::utils::debug 5 "Prepended '$val' to argument $opt ==> '$ARY($opt)'"
	    lappend modified $opt
	} elseif { [string index $extracted end] eq ">" } {
	    set ARY($opt) $ARY($opt)\ $val
	    ::utils::debug 5 "Appended '$val' to argument $opt ==> '$ARY($opt)'"
	    lappend modified $opt
	} else {
	    set ARY($opt) $val
	    ::utils::debug 5 "Set argument $opt to '$ARY($opt)'"
	    lappend modified $opt
	}
    }
    
    return [lsort -unique $modified]
}


proc ::utils::Mapper { _lst args } {
    variable UTILS

    if { $_lst ne "" } {
	upvar $_lst lst
    }

    foreach {k v} $args {
	foreach s $UTILS(subst) {
	    lappend lst $s$k$s $v
	}
    }

    return $lst
}


proc ::utils::dbgfmt { lvl pkg output } {
    variable UTILS

    set hdr [string map [Mapper "" pkg $pkg] $UTILS(dateLogHeader)]
    set hdr [clock format [clock seconds] -format $hdr]
    return ${hdr}${output}
}


proc ::utils::chkopt { _ary args } {
    upvar $_ary ARY

    set failed {}
    foreach { opt check } $args {
	set opt "-[string trimleft $opt -]"
	if { [info exist $ARY($opt)] \
		 && ![string is $check -strict $ARY($opt)] } {
	    lappend failed $opt $check
	}
    }
    return $failed
}


# ::utils::debug -- Conditional debug output
#
#       Output debug message depending on the debug level that is
#       currently associated to the library.  Debug occurs on the
#       registered file descriptor.
#
# Arguments:
#	lvl	Debug level of message, lib. level must be lower for input
#	output	Message to write out, possibly
#
# Results:
#       None.
#
# Side Effects:
#       Write message onto debug file descriptor, if applicable.
proc ::utils::debug { lvl output { pkg "" } } {
    global argv0
    variable UTILS

    set lvl [LogLevel $lvl]

    if { $pkg eq "" } {
	set pkg [lindex [split [string trim [uplevel 1 namespace current] ":"] ":"] end]
	if { $pkg eq "" } {
	    if { $UTILS(fullpath) eq "" } {
		set UTILS(fullpath) [file normalize $argv0]
	    }
	    set pkg [file rootname [file tail $UTILS(fullpath)]]
	}
    }

    foreach { ptn verbosity } $UTILS(verbose) {
	if { [string match $ptn $pkg] } {
	    if {[LogLevel $verbosity] >= $lvl } {
		if { [string index $UTILS(dbgfd) 0] eq "@" } {
		    set cmd [string range $UTILS(dbgfd) 1 end]
		    if { [catch {eval [linsert $cmd end $lvl $pkg $output]} err] } {
			puts stderr "Cannot callback external log command: $err"
		    }
		} else {
		    puts $UTILS(dbgfd) [dbgfmt $lvl $pkg $output]
		}
	    }
	    return
	}
    }
}


# ::utils::logger -- Arrange to output log to file (descriptor)
#
#       This procedure will send the output log to a file.  If it is
#       called with the path to a file, the file will be appended for
#       log output.  Otherwise the argument is understood as being an
#       already opened file descriptor.  Existing logging to another
#       log file will be cancelled before new logging is setup.
#
# Arguments:
#	fd	File descriptor, path to file or command
#
# Results:
#       Returns the file descriptor used for logging.
#
# Side Effects:
#       None.
proc ::utils::logger { fd_or_n } {
    variable UTILS

    if { [string index $fd_or_n 0] eq "@" } {
	set fd $fd_or_n
    } else {
	# Open file for appending if it is a file, otherwise consider the
	# argument as a file descriptor.
	if { [catch {fconfigure $fd_or_n}] } {
	    debug 3 "Appending log to $fd_or_n"
	    if { [catch {open $fd_or_n a} fd] } {
		debug 2 "Could not open $fd_or_n: $fd"
		return -code error "Could not open $fd_or_n: $fd"
	    }
	} else {
	    set fd $fd_or_n
	}
    }

    # Close previous debug file descriptor if it was not a standard
    # one and setup new one.
    if { ![string match std* $UTILS(dbgfd)] } {
	catch {close $UTILS(dbgfd)}
    }
    if { [string index $fd 0] ne "@" } {
	fconfigure $fd -buffering line
    }
    set UTILS(dbgfd) $fd
    debug 3 "Log output successfully changed to new target"

    return $UTILS(dbgfd)
}


# ::utils::verbosity -- Set module verbosity
#
#       Change the verbosity for modules. This procedure should take
#       an even-long list, where each odd argument is a pattern (to be
#       matched against the name of the existing logging modules) and
#       even arguments is the log level for the matching module(s).
#
# Arguments:
#	args	Even-long list of verbosity specification for modules.
#
# Results:
#       Return old verbosity levels
#
# Side Effects:
#       None.
proc ::utils::verbosity { args } {
    variable UTILS

    set old $UTILS(verbose)
    set UTILS(verbose) {}
    foreach { spec lvl } $args {
	set lvl [LogLevel $lvl]
	if { [string is integer $lvl] && $lvl >= 0 } {
	    lappend UTILS(verbose) $spec $lvl
	}
    }
    
    if { $old ne $UTILS(verbose) } {
	debug 4 "Changed module verbosity to: $UTILS(verbose)"
    }

    return $old
}


# ::utils::Identifier -- Return a unique identifier
#
#       Generate a well-formated unique identifier to be used, for
#       example, to generate variable names or similar.
#
# Arguments:
#	pfx	String prefix to prepend to id, empty for none
#
# Results:
#       A (possibly prefixed) unique identifier in space and time
#       (almost).
#
# Side Effects:
#       None.
proc ::utils::identifier { {pfx "" } } {
    variable UTILS

    set unique [incr UTILS(idGene)]
    append unique [expr {[clock clicks -milliseconds]%$UTILS(idClamp)}]
    append pfx [format "%.$UTILS(idFormat)d" $unique]
}


# ::utils::resolve -- Resolve %-sugared string in text
#
#       This procedure will resolve the content of "variables" (see
#       next), enclosed by %-signs to their content.  By default, the
#       variables recognised are all the keys of the tcl_platform
#       array, all environment variables and prgdir and prgname, which
#       are resolved from the full normalized path to the program.
#       The procedure also takes an additional even-long list of
#       variables that can occur as part of this resolution.  If the
#       value of a variable contains itself %-enclosed variables,
#       these will also be resolved.  The procedure guarantee a finite
#       number of iterations to avoid infinite loops.
#
# Arguments:
#	txt	Text to be resolved
#	keys	Additional even-long list of vars and values.
#
# Results:
#       The resolved string, after a finite number of iterations.
#
# Side Effects:
#       None.
proc ::utils::resolve { txt { keys {} } } {
    variable UTILS

    # Generate a mapper that we will be able to quickly resolve
    # non-defaulting expressions with.
    set keys [Keys $keys]
    set mapper {}
    foreach {k v} $keys {
	Mapper mapper $k $v
    }
    
    # Recursively map, meaning that we can use the content of keys in
    # keys...
    for { set i 0 } { $i < $UTILS(maxresolve) } { incr i } {
	set rtxt [string map $mapper $txt]
	if { $rtxt eq $txt } {
	    return [Defaults $rtxt $keys]
	}
	set txt $rtxt
    }

    debug 2 "Maximum number of resolution iterations reached!"
    return [Defaults $txt $keys]
}


# ::utils::dispatch -- Library dispatcher
#
#       This is a generic library dispatcher that is used to offer a
#       tk-style object-like API for objects that would be created in
#       another namespace.  This will refuse to dispatch protected
#       (internal) procedures.
#
# Arguments:
#	obj	Identifier of object (typically from utils::identifier)
#	ns	FQ namespace where to dispatch
#	method	Method to call (i.e. one of the exported procs in the namespace)
#	args	Arguments to pass to the procedure after the identifier
#
# Results:
#       Whatever is returned by the called procedure.
#
# Side Effects:
#       None.
proc ::utils::dispatch { obj ns method args} {
    if { [string match \[a-z\] [string index $method 0]] } {
	if { [info commands ${ns}::${method}] eq "" } {
	    return -code error "Cannot find $method in $ns!"
	}
    } else {
	return -code error "$method is internal to $ns!"
    }
    namespace inscope $ns $method $obj {*}$args
}


proc ::utils::rdispatch { obj ns methods method args} {
    foreach meths $methods {
	foreach m $meths {
	    if { [string equal $m $method] } {
		return [dispatch $obj $ns [lindex $meths 0] {*}$args]
	    }
	}
    }
    return -code error "$method is not allowed in $ns!"
}


proc ::utils::mset { ns varvals {pfx ""} } {
    foreach {k v} $varvals {
	if { $pfx ne "" } {
	    set k ${pfx}[string trimleft $k $pfx]
	}
	if { [info exists ${ns}::${k}] } {
	    set ${ns}::${k} $v
	}
    }

    set state {}
    foreach v [info vars ${ns}::${pfx}*] {
	lappend state [lindex [split $v ":"] end] [set $v]
    }
    return $state
} 


proc ::utils::Keys { {keys {}} } {
    variable UTILS
    global env tcl_platform argv0
    
    set mapper {}
    foreach {k v} [array get tcl_platform] {
	lappend mapper $k $v
    }
    foreach {k v} [array get env] {
	lappend mapper $k $v
    }
    foreach {k v} $keys {
	if { [string trim $k] ne "" && [string trim $v] ne "" } {
	    lappend mapper $k $v
	}
    }
    if { $UTILS(fullpath) eq "" } {
	set UTILS(fullpath) [file normalize $argv0]
    }
    lappend mapper progdir [file dirname $UTILS(fullpath)]
    lappend mapper prgdir [file dirname $UTILS(fullpath)]
    lappend mapper progname [file rootname [file tail $UTILS(fullpath)]]
    lappend mapper prgname [file rootname [file tail $UTILS(fullpath)]]

    return $mapper
}


proc ::utils::Defaults { txt {keys {}}} {
    variable UTILS

    array set CURRENT $keys
    foreach s $UTILS(subst) {
	foreach separator $UTILS(dflt_sep) {
	    # Generate a regular expression that will match strings
	    # enclosed by the substitutions characters with one of the
	    # defaulting separators.  We backslash the parenthesis to
	    # avoid them as being understood as indices in arrays.  We
	    # backslash the separator to make sure we match on the
	    # character and nothing else.  We group to easily find out
	    # the default value below.
	    set rx "${s}\(.*?\)\\${separator}\(.*?\)${s}"
	    
	    if { [llength [split $txt $separator]] <= 2 } {
		# Replace all occurences of what looks like defaulting
		# instructions to the default that they contain.
		while 1 {
		    # Find next match in string and break out of loop if
		    # none found.
		    set match [regexp -all -inline -indices -- $rx $txt]
		    if { [llength $match] == 0 } {
			break
		    }
		    # Access the match, all these will be pairs of
		    # indices.
		    foreach {m v dft} $match break
		    # Extract the (default) value from the string and
		    # relace the whole defaulting construct with the
		    # default value or the value of the key
		    set k [string range $txt [lindex $v 0] [lindex $v 1]]
		    if { [info exists CURRENT($k)] } {
			set val $CURRENT($k)
		    } else {
			set val [string range $txt [lindex $dft 0] [lindex $dft 1]]
		    }
		    set txt [string replace $txt [lindex $m 0] [lindex $m 1] $val]
		}
	    }
	}
    }
    return $txt
}


proc ::utils::lclean { lst } {
    variable UTILS

    set vals [list]
    foreach e $lst {
	set line [string trim $e]
	if { $line ne "" } {
	    set firstchar [string index $line 0]
	    if { [string first $firstchar $UTILS(comments)] < 0 } {
		# Allow to add empty values
		if { [lsearch -exact $UTILS(empty) $line] >= 0 } {
		    lappend vals ""
		} else {
		    if { [string index $line 0] eq "\"" \
			     && [string index $line end] eq "\"" } {
			lappend vals [string trim $line \"]
		    } else {
			lappend vals $line
		    }
		}
	    }
	}
    }
    return $vals
}


proc ::utils::lscan { data { divider -1 } { type "data" } } {
    set data [string map [list "\r\n" "\n" "\r" "\n"] $data]
    set vals [lclean [split $data "\n"]]

    set len [llength $vals]
    if { $divider > 0 } {
	if { [expr {$len % $divider}] != 0 } {
	    set keep [expr {($len / $divider)*$divider}]
	    debug 3 "$type contained $len elements,\
                     wrong numer! Keeping $keep first ones"
	    set vals [lrange $vals 0 [expr {$keep - 1}]]
	} else {
	    debug 5 "Read $len elements from $type"
	}
    } else {
	debug 5 "Read $len elements from $type"
    }
    return $vals
}


# ::utils::lread -- Read lists from file
#
#       This is a generic "list reading" procedure that will read the
#       content of files where each line represents one element of a
#       list.  The procedure will gracefully ignore comments and empty
#       lines, thus providing a raw mechanism for reading
#       configurations files in a number of cases.  The procedure is
#       also able to count and control the number of elements in the
#       list that is read, forcing them to be a multiplier of xx and
#       cutting away the last elements not following the rule if
#       necessary.  This makes it perfect for parsing the result of
#       file reading using a foreach command.
#
# Arguments:
#	fname	Path to file to read
#	divider	Multiplier for number of elements, negative or zero to turn off
#	type	Type of file being read, used for logging output only.
#
# Results:
#       Return the elements contained in the file as a list.  If the
#       number of elements in the list had to be a multiplier of xx,
#       ending elements that do not follow the rule (if any) are
#       removed.  The list is empty on errors (or when no elements
#       were contained in the file.
#
# Side Effects:
#       None.
proc ::utils::lread { fname { divider -1 } { type "file" } } {
    variable UTILS
    
    set vals [list]
    debug 4 "Reading $type from $fname"
    if { [catch {open $fname} fd] } {
	debug 2 "Could not read $type from $fname: $fd"
    } else {
	while { ! [eof $fd] } {
	    lappend vals [gets $fd]
	}
	close $fd
	set vals [lclean $vals]

	set len [llength $vals]
	if { $divider > 0 } {
	    if { [expr {$len % $divider}] != 0 } {
		set keep [expr {($len / $divider)*$divider}]
		debug 3 "$type $fname contained $len elements,\
                         wrong numer! Keeping $keep first ones"
		set vals [lrange $vals 0 [expr {$keep - 1}]]
	    } else {
		debug 5 "Read $len elements from $type $fname"
	    }
	} else {
	    debug 5 "Read $len elements from $type $fname"
	}
    }

    return $vals
}


proc ::utils::sed {script input} {
    set sep [string index $script 1]
    foreach {cmd from to flag} [split $script $sep] break
    switch -- $cmd {
	"s" {
	    set cmd regsub
	    if {[string first "g" $flag]>=0} {
		lappend cmd -all
	    }
	    if {[string first "i" [string tolower $flag]]>=0} {
		lappend cmd -nocase
	    }
	    set idx [regsub -all -- {[a-zA-Z]} $flag ""]
	    if { [string is integer -strict $idx] } {
		set cmd [lreplace $cmd 0 0 regexp]
		lappend cmd -inline -indices -all -- $from $input
		set res [eval $cmd]
		set which [lindex $res $idx]
		return [string replace $input [lindex $which 0] [lindex $which 1] $to]
	    }
	    # Most generic case
	    lappend cmd -- $from $input $to
	    return [eval $cmd]
	}
	"e" {
	    set cmd regexp
	    if { $to eq "" } { set to 0 }
	    if {![string is integer -strict $to]} {
		return -error code "No proper group identifier specified for extraction"
	    }
	    lappend cmd -inline -- $from $input
	    return [lindex [eval $cmd] $to]
	}
	"y" {
	    return [string map [list $from $to] $input]
	}
    }
    return -code error "not yet implemented"
}


# ::utils::LogLevel -- Convert log levels
#
#       For convenience, log levels can also be expressed using
#       human-readable strings.  This procedure will convert from this
#       format to the internal integer format.
#
# Arguments:
#	lvl	Log level (integer or string).
#
# Results:
#       Log level in integer format, -1 if it could not be converted.
#
# Side Effects:
#       None.
proc ::utils::LogLevel { lvl } {
    variable UTILS

    if { ![string is integer $lvl] } {
	foreach {l str} $UTILS(verboseTags) {
	    if { [string match -nocase $str $lvl] } {
		return $l
	    }
	}
	return -1
    }
    return $lvl
}


package provide utils 0.1;
