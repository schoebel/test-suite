#!/bin/bash
#
# Copyright 2014 Thomas Schoebel-Theuer
# Programmed in my spare time on my private notebook.
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA

# 0 = don't repair => leave node dead
# 1 = invalidate
# 2 = down; leave-resource ; join-resource
##### the following is NOT RECOMMENDED => ignore disk state of current primary and use disk of a secondary => may lead to DATA LOSS
# 3 = down; leave-resource ; delete-resource --force ; create-resource --force => leave other nodes dead
# 4 = dito ; Kill old primary by umount ; leave-resource --force => old primary now reusable
# 5 = dito ; Repair other nodes with join-resource
conf_repair_mode="${conf_repair_mode:-1}"
conf_repair_intermediate_secondary=${conf_repair_intermediate_secondary:-0}

function _REPAIR_start
{
    local host_list="${1:-$state_bad_list}"

    if [[ "$state_primary" != "" ]] && [[ "$(list_intersect "$host_list" "$state_primary")" != "" ]]; then
	"Sorry, you cannot repair the current primary host '$state_primary'"
	script_fail 1
    fi
    if (( conf_repair_mode >= 5 && $(echo "const_host_list" | wc -w) > 2 )); then
	"Sorry, repair mode 5 works only on 2 nodes."
	script_fail 1
    fi

    _SETUP_mount_stop "$host_list"
    remote_add "$host_list" "$marsadm wait-umount all || exit \$?"
    cluster_wait

    local lv
    if (( conf_repair_mode == 1 )); then
	for lv in $(_get_lv_list); do
	    remote_add "$host_list" "$marsadm invalidate $lv --verbose || exit \$?"
	done
	remote_wait
	state_bad_list="$(list_minus "$state_bad_list" "$host_list")"
    elif (( conf_repair_mode == 2 )); then
	local host
	for host in "$host_list"; do
	    for lv in $(_get_lv_list); do
		remote_add "$host" "$marsadm down $lv || exit \$?"
		remote_add "$host" "$marsadm leave-resource $lv --verbose || exit \$?"
	    done
	    cluster_wait
	done
	for lv in $(_get_lv_list); do
	    remote_add "$state_primary" "$marsadm log-purge-all $lv --force || exit \$?"
	done
	cluster_wait
	for lv in $(_get_lv_list); do
	    remote_add "$host_list" "$marsadm join-resource $lv /dev/$const_vg_name/$lv || exit \$?"
	done
	remote_wait
	state_bad_list="$(list_minus "$state_bad_list" "$host_list")"
    elif (( conf_repair_mode >= 3 && conf_repair_mode <= 5 )); then
	local count="$(echo $host_list | wc -w)"
	if (( count > 1 )); then
	    echo "Cannot use conf_repair_mode='$conf_repair_mode' on $count hosts" >> /dev/stderr
	    echo "host_list='$host_list'" >> /dev/stderr
	    echo "HINT: by its very nature, it can only work on exactly 1 host!" >> /dev/stderr
	    script_fail 1
	fi
	echo "Repair method $conf_repair_mode is NOT RECOMMENDED -- checking that it works anyway"
	for lv in $(_get_lv_list); do
	    if (( conf_repair_intermediate_secondary )); then # not recommeded
		# remove _all_ loads (otherwise 'secondary' refuses to work)
		_SETUP_mount_stop "$state_primary"
		remote_add "$state_primary" "$marsadm wait-umount all || exit \$?"
		cluster_wait
		remote_add "$host_list" "$marsadm secondary $lv || exit \$?"
	    fi
	    remote_add "$host_list" "$marsadm down $lv || exit \$?"
	    remote_add "$host_list" "$marsadm leave-resource $lv || exit \$?"
	    remote_add "$host_list" "$marsadm delete-resource --force $lv || exit \$?"
	    remote_add "$host_list" "$marsadm create-resource --force $lv /dev/$const_vg_name/$lv || exit \$?"
	done
	remote_wait

	state_primary_old="$state_primary"
	state_primary="$host_list"
	state_bad_list="$(list_minus "$const_host_list" "$state_primary")"
	_update_state

	if (( conf_repair_mode >= 4 )); then
	    (( verbose )) && echo "++++++++++++++++++ killing old primary $state_primary_old"
	    _SETUP_mount_stop "$state_primary_old"
	    remote_add "$state_primary_old" "$marsadm wait-umount all || echo 'IGNORING error \$?'"
	    remote_add "$state_primary_old" "$marsadm leave-resource --force $lv || echo 'IGNORING error \$?'"
	    remote_wait
	fi
	if (( conf_repair_mode >= 5 )); then
	    (( verbose )) && echo "++++++++++++++++++ restarting repair of $(echo "$state_bad_list" | wc -w) other hosts"
	    cluster_wait
	    for lv in $(_get_lv_list); do
		remote_add "$state_bad_list" "$marsadm join-resource $lv /dev/$const_vg_name/$lv || exit \$?"
	    done
	    remote_wait
	    state_bad_list=""
	fi
    else
	echo "Unknown conf_repair_mode='$conf_repair_mode'" >> /dev/stderr
	script_fail 1
    fi
    _update_state
}

function REPAIR_start
{
    local host_list="${1:-$state_bad_list}"

    if (( conf_repair_mode <= 0 )) || [[ "$host_list" == "" ]]; then
	(( verbose )) && echo "++++++++++++++++++ skipping repair"
	return 0
    fi
    (( verbose )) && echo "++++++++++++++++++ repairing $host_list in mode $conf_repair_mode"
    _REPAIR_start "$host_list"
}

function REPAIR_wait
{
    remote_wait
}

function REPAIR
{
    REPAIR_start
    REPAIR_wait
}
