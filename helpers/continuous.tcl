#! /usr/bin/env tclsh

# The code in this file can be used to ensure that a process under the control
# of concocter will always be restarted whenever it has ended (and for whichever
# reason). To trigger this behaviour, you should start concocter with the
# following options (adapt 10 to the number of seconds at which you wish to
# check the content of your variables, templates and presence of process under
# your control)
#
#     -update 10 -external keepalive@%progdir%/helpers/continuous.tcl
#
# The main startup line at the end of the script means that you should also be
# able to write the -external option as -external
# %progdir%/helpers/continuous.tcl. This is however less effective.



# The procedure below will return 1 whenever the PID passed as a parameter is
# negative, 0 otherwise. The PID passed as a parameter will be positive, by
# design, whenever the process under our control is still running at the time of
# the call.
proc keepalive { pid } {
    return [expr {$pid < 0}]
}

# Relay the command-line argument to the keepalive procedure for the lazy ones.
return [keepalive [lindex $argv 0]]