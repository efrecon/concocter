proc reverter { block } {
    set revs [list]
    foreach l [split $block \n] {
        set mirror [list]
        foreach c [split $l ""] {
            set mirror [linsert $mirror 0 $c]
        }
        set revs [linsert $revs 0 [join $mirror ""]]
    }
    return [join $revs \n]
}