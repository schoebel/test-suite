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

state_checkable=0
state_check_list=""
function CHECK_start
{
    local host_list="${1:-$(list_minus "$const_host_list" "$state_bad_list")}"

    state_checkable=0
    if (( $(echo $host_list | wc -w) < 2 )); then
	if (( verbose )); then
	    echo "++++++++++++++++++ skipping resource checks"
	    echo "Too less hosts are operational: '$host_list'"
	fi
	return 0
    fi

    (( verbose )) && echo "++++++++++++++++++ checking resources"
    _SETUP_mount_stop
    remote_add "$host_list" "iptables -F"
    remote_add "$host_list" "$marsadm resume-fetch all || exit \$?"
    remote_add "$host_list" "$marsadm resume-replay all || exit \$?"
    RESOURCE_wait

    state_checkable=1
    state_check_list="$host_list"
    # check that primary has flushed everything
    remote_add "$state_primary" "$marsadm view all"
    remote_wait "$pred_all_flushed"
    # check that secondaries are fully applied
    cluster_wait # protect against race if the network was cut
    for lv in $(_get_lv_list); do
	remote_add "$state_secondary_list" "$marsadm view $lv"
	remote_wait "$pred_lv_applied"
	if (( state_load[$state_primary] )); then
	    remote_add "$state_primary" "ls -la /mnt/test/$lv"
	fi
    done
    # detach everything and checksum
    remote_add "$host_list" "$marsadm down all || exit \$?"
    for lv in $(_get_lv_list); do
	remote_add "$state_primary $state_secondary_list" "size=\"\$(readlink /mars/resource-$lv/size || exit \$?)\""
	remote_add "$state_primary $state_secondary_list" "(( count = size / 4096 ))"
	remote_add "$state_primary $state_secondary_list" "echo \"COMPARE \$(dd if=/dev/$const_vg_name/$lv bs=4096 count=\$count | md5sum || exit \$?)\""
    done
    remote_start
}

function CHECK_wait
{
    remote_wait

    if (( state_checkable )); then
	remote_add "$state_check_list" "$marsadm up all || exit \$?"
	# remote_start is deliberately not called.
	# There is a chance to never execute it (e.g. at the end of the test,
	# in order to see the last state of MARS), or to do remote_reset later.
    fi
}

function CHECK
{
    CHECK_start
    CHECK_wait
}
