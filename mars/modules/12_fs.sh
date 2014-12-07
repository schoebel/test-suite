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

conf_fs_type="${conf_fs_type:-xfs}"

# 0 = don't create at all
# 1 = earliest, before resource is created
# 2 = after resource creation, before sync
# 3 = after sync
conf_fs_mode="${conf_fs_mode:-1}"

declare -A state_fs_mounted

function _SETUP_mount_stop
{
    local host_list="${1:-$const_host_list}"

    _LOAD_stop "$host_list"
    remote_add "$host_list" "for i in \$(cut -d' ' -f2 < /proc/mounts | grep '/mnt/test'); do umount -f \$i; done"
    remote_wait
    declare -A -g state_fs_mounted
    local i
    for i in $host_list; do
	state_fs_mounted[$i]=0
    done
}

function _SETUP_mount_start
{
    local host_list="${1:-$state_primary}"
    local lv_list="${2:-$(_get_lv_list)}"

    local lv
    for lv in $lv_list; do
	local dir="/mnt/test/$lv"
	remote_add "$host_list" "mkdir -p $dir"
	remote_add "$host_list" "mount /dev/mars/$lv $dir || exit \$?"
    done
    declare -A -g state_fs_mounted
    local i
    for i in $host_list; do
	state_fs_mounted[$i]=1
    done
}

function SETUP_mount_start
{
    local host_list="${1:-$state_primary}"
    local lv_list="${2:-$(_get_lv_list)}"

    (( verbose )) && echo "++++++++++++++++++ mounting filesystems $lv_list on $host_list"
    _SETUP_mount_start "$host_list" "$lv_list"
}

function SETUP_fs_start
{
    if [[ "$conf_fs_type" = "" ]] || (( conf_fs_mode <= 0 )); then
	(( verbose )) && echo "++++++++++++++++++ skipping creation of filesystems"
	return 0
    fi
    (( verbose )) && echo "++++++++++++++++++ creating $conf_fs_type filesystems"
    for lv in $(_get_lv_list); do
	if (( conf_fs_mode == 1 )); then
	    remote_add "$state_primary" "mkfs -t $conf_fs_type /dev/$const_vg_name/$lv || exit \$?"
	else
	    remote_wait
	    remote_add "$state_primary" "$marsadm view-present-device $lv"
	    remote_wait "$pred_is_1"
	    remote_add "$state_primary" "mkfs -t $conf_fs_type /dev/mars/$lv || exit \$?"
	fi
    done
    if (( conf_fs_mode > 1 )); then
	SETUP_mount_start
    fi
}

function SETUP_fs_wait
{
    remote_wait
}

function SETUP_fs
{
    SETUP_fs_start
    SETUP_fs_wait
}
