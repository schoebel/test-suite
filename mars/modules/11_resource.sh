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

conf_lv_count="${conf_lv_count:-1}"
conf_lv_size="${conf_lv_size:-2G}"

function _get_lv_list
{
    local i=0
    while (( i < conf_lv_count )); do
	echo "lv-$i"
	(( i++ ))
    done
}

function RESOURCE_wait
{
    cluster_wait
    for lv in $(_get_lv_list); do
	remote_add "$state_secondary_list" "$marsadm view $lv"
	remote_wait "$pred_lv_uptodate"
    done
}

function SETUP_resource_start
{
    remote_wait
    (( verbose )) && echo "++++++++++++++++++ creating resources"
    local lv
    for lv in $(_get_lv_list); do
	remote_add "$const_host_list" "lvcreate -L $conf_lv_size -n $lv $const_vg_name || exit \$?"
	if (( conf_fs_mode == 1 )); then
	    SETUP_fs_start
	    remote_wait
	    remote_add "$state_primary" "$marsadm view-present-device $lv"
	    remote_wait "$pred_is_1"
	    SETUP_mount_start
	fi
	remote_add "$state_primary" "$marsadm create-resource $lv /dev/$const_vg_name/$lv || exit \$?"
    done

    remote_start "$state_primary"
    wait
    (( conf_fs_mode == 2 )) && SETUP_fs_start

    cluster_wait
    for lv in $(_get_lv_list); do
	remote_add "$state_secondary_list" "$marsadm join-resource $lv /dev/$const_vg_name/$lv || exit \$?"
    done
    remote_start
}

function SETUP_resource_wait
{
    (( verbose )) && echo "++++++++++++++++++ waiting for resource sync"
    RESOURCE_wait
    (( conf_fs_mode == 3 )) && SETUP_fs
}

function SETUP_resource
{
    SETUP_resource_start
    SETUP_resource_wait
}

function SETUP
{
    SETUP_cluster
    SETUP_resource
}
