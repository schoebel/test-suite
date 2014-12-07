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

const_net_dev="${const_net_dev:-eth0}"

conf_net_bottle_max="${conf_net_bottle_max:-0}" # kbit/s
conf_net_bottle_min="${conf_net_bottle_min:-100}" # kbit/s
conf_net_bottle_window="${conf_net_bottle_window:-30}" # s

conf_net_delay="${conf_net_delay:-150}"
conf_net_ports="${conf_net_ports:-7777:7779}"

check_install_list="$check_install_list tc"

declare -A state_net_bottle

function IMPACT_net_bottle_start
{
    local host_list="${1:-$const_host_list}"

    (( conf_net_bottle_max <= 0 )) && return 0

    (( verbose )) && echo "++++++++++++++++++ network bottleneck on $host_list"

    declare -A -g state_net_bottle
    local host
    for host in $host_list; do
	state_net_bottle[$host]=1
    done

    local pt
    for pt in sport dport; do
	local rule="iptables -t mangle -A PREROUTING -p tcp --$pt $conf_net_ports -j MARK --set-mark 9"
	remote_add "$host_list" "$rule || exit \$?"
    done


    local tc
    tc="tc qdisc add dev $const_net_dev root handle 1: prio"
    remote_add "$host_list" "$tc || exit \$?"

    local tc_parm="buffer 128000 latency 1s minburst 64000"
    tc="tc qdisc add dev $const_net_dev parent 1:3 handle 30: tbf rate ${conf_net_bottle_max}kbit $tc_parm"
    remote_add "$host_list" "$tc || exit \$?"

    tc="tc qdisc add dev $const_net_dev parent 30:1 handle 31: netem delay ${conf_net_delay}ms 5ms distribution normal"
    remote_add "$host_list" "$tc || exit \$?"

    local pt
    for pt in sport dport; do
	# shape the mars ports
	local p
	for p in $(eval echo {${conf_net_ports/:/..}}); do
	    tc="tc filter add dev $const_net_dev protocol ip parent 1:0 prio 3 u32 match ip $pt $p 0xffff flowid 1:3"
	    remote_add "$host_list" "$tc || exit \$?"
	done
	# except ssh port 22
	tc="tc filter add dev $const_net_dev protocol ip parent 1:0 prio 3 u32 match ip $pt 22 0xffff flowid 1:1"
	remote_add "$host_list" "$tc || exit \$?"
    done
    remote_wait

    local -a args
    local i=0
    args[$(( i++ ))]="rm -f MARS-bottle.log"
    args[$(( i++ ))]="while true; do"
    args[$(( i++ ))]="  rest=\\\$(( \\\$(for host in $host_list; do ssh \"\\\$host\" \"marsadm view-fetch-rest all\"; done | grep '^[0-9]\+$' | sed 's/^/+/') ))"
    args[$(( i++ ))]="  (( rate = rest / 1024 / $conf_net_bottle_window ))"
    args[$(( i++ ))]="  (( rate = ( rate < $conf_net_bottle_max ) ? rate : $conf_net_bottle_max ))"
    args[$(( i++ ))]="  (( rate = ( rate > $conf_net_bottle_min ) ? rate : $conf_net_bottle_min ))"
    args[$(( i++ ))]="  for host in $host_list; do"
    args[$(( i++ ))]="    ssh \"\\\$host\" \"tc qdisc change dev $const_net_dev parent 1:3 handle 30: tbf rate \\\${rate}kbit $tc_parm\" &"
    args[$(( i++ ))]="  done"
    args[$(( i++ ))]="  echo \"\\\$(date) \\\$rest \\\$rate\" >> MARS-bottle.log"
    args[$(( i++ ))]="  wait"
    args[$(( i++ ))]="  sleep 1"
    args[$(( i++ ))]="done &"
    remote_script_add "$state_primary" "1" "bottle" "${args[@]}"
    remote_wait    
}

function IMPACT_net_bottle_stop
{
    local host_list="${1:-$const_host_list}"

    (( conf_net_bottle_max <= 0 )) && return 0

    (( verbose )) && echo "++++++++++++++++++ remove network bottleneck from $host_list"

    remote_reset
    remote_add "$host_list" "while killall -r MARS-bottle; do sleep 1; done"

    declare -A -g state_net_bottle
    local host
    for host in $host_list; do
	state_net_bottle[$host]=0
    done

    remote_add "$host_list" "iptables -t mangle -F"

    local tc
    tc="tc -s qdisc ls dev $const_net_dev"
    remote_add "$host_list" "$tc"
    tc="tc -s filter ls dev $const_net_dev"
    remote_add "$host_list" "$tc"

    tc="tc qdisc delete dev $const_net_dev root"
    remote_add "$host_list" "$tc"
    tc="tc filter delete dev $const_net_dev root"
    remote_add "$host_list" "$tc"
    remote_add "$host_list" "true"

    cluster_wait
}

