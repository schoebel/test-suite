#!/bin/bash

# 0 = disable
# 1 = stop the load
# 2 = dito ; additionally switch to 'secondary' state (NOT RECOMMENDED)
conf_unload_enable="${conf_unload_enable:-0}"

function IMPACT_unload
{
    local host_list="${1:-$state_primary}"
    local enable="${2:-$conf_unload_enable}"

    (( enable <= 0 )) && return 0
    remote_wait

    (( verbose )) && echo "++++++++++++++++++ stopping load ($enable) on $host_list"
    _SETUP_mount_stop "$host_list"
    remote_add "$host_list" "$marsadm wait-umount all || exit \$?"
    remote_wait
    if (( enable >= 2 )); then
	remote_add "$host_list" "$marsadm secondary all || exit \$?"
	remote_wait
    fi
    cluster_wait
}
