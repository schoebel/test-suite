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

const_vg_name="${const_vg_name:-vg00}"
const_fail_timeout="${const_fail_timeout:-20}"

conf_mars_size="${conf_mars_size:-15G}"
conf_mars_fs_type="${conf_mars_fs_type:-ext4}"

marsadm="${marsadm:-marsadm </dev/null}"

check_install_list="$check_install_list lsmod rmmod modinfo iptables mkfs mount umount pvcreate pvremove vgcreate vgremove lvcreate lvremove ${marsadm%% *}"

function cluster_wait
{
    local host_list="${1:-$const_host_list}"

    remote_wait
    declare -A -g state_net_cut
    if (( state_net_cut[$state_primary] )); then
	return 0
    fi

    remote_add "$host_list" "$marsadm wait-cluster"
    remote_wait
}

function CLEANUP_mars
{
    remote_reset
    (( verbose )) && echo "++++++++++++++++++ cleanup everything"
    remote_add "$const_host_list" "killall marsadm"
    remote_add "$const_host_list" "killall -r MARS || echo ignore"
    _SETUP_mount_stop
    remote_add "$const_host_list" "if lsmod | grep -q mars; then sleep 3; rmmod mars; fi"
    remote_add "$const_host_list" "umount -f /mars/ && sleep 1"
    remote_add "$const_host_list" "for i in /dev/$const_vg_name/*; do lvremove -f \$i; done"
    remote_add "$const_host_list" "iptables -F"
    remote_add "$const_host_list" "iptables -t mangle -F"
    local tc
    tc="tc qdisc delete dev $const_net_dev root"
    remote_add "$const_host_list" "$tc"
    tc="tc filter delete dev $const_net_dev root"
    remote_add "$const_host_list" "$tc"
    remote_add "$const_host_list" "true"
    remote_wait
}

function SETUP_cluster_start
{
    CLEANUP_mars
    (( verbose )) && echo "++++++++++++++++++ creating cluster"
    remote_add "$const_host_list" "cat /proc/version"
    remote_add "$const_host_list" "modinfo mars"
    remote_add "$const_host_list" "lvcreate -L $conf_mars_size -n lv-mars $const_vg_name || exit \$?"
    remote_wait
    remote_add "$const_host_list" "[[ -b /dev/$const_vg_name/lv-mars ]]; echo \$?"
    remote_wait "$pred_is_0"
    remote_add "$const_host_list" "mkfs -t $conf_mars_fs_type /dev/$const_vg_name/lv-mars || exit \$?"
    remote_add "$const_host_list" "mkdir -p /mars"
    remote_add "$const_host_list" "mount /dev/$const_vg_name/lv-mars /mars/ || exit \$?"
    remote_add "$const_host_list" "touch /mars/5.total.log"
    remote_add "$state_primary" "$marsadm create-cluster || exit \$?"
    remote_wait
    remote_add "$state_secondary_list" "$marsadm join-cluster $state_primary || exit \$?"
    remote_add "$const_host_list" "echo 3 > /proc/sys/vm/drop_caches"
    remote_add "$const_host_list" "modprobe mars || exit \$?"
    remote_add "$const_host_list" "echo 1 > /proc/sys/mars/show_debug_messages"
    remote_add "$const_host_list" "echo 1 > /proc/sys/mars/show_statistics_global"
#    remote_add "$const_host_list" "echo 1 > /proc/sys/mars/show_statistics_server"
    remote_start
}

function SETUP_cluster_wait
{
    remote_wait
#hotfix
sleep 5
}

function _check_logfiles
{
    (( verbose )) && echo "++++++++++++++++++ saving logfiles"
    remote_reset

    local dir="$log_dir/result-logs-$start_date/$(date +%Y%m%d_%H%M%S)"
    mkdir -p $dir
    local host
    for host in $const_host_list; do
	ssh root@$host "cat /mars/5.total.log | nice gzip -9" > ${dir}/${host}.total.log.gz &
    done
    wait

    ## provis
    remote_add "$const_host_list" "! grep 'MEM_err\|MEMLEAK' /mars/5.total.log"
    remote_wait
}

function SETUP_cluster
{
    hooks_testcase_poststart+=" _check_logfiles"
    SETUP_cluster_start
    SETUP_cluster_wait
}
