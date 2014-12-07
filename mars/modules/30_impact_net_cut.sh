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

conf_net_cut="${conf_net_cut:-0}"
conf_net_ports="${conf_net_ports:-7777:7779}"

declare -A state_net_cut

function IMPACT_net_cut_start
{
    local host_list="${1:-$state_primary}"

    (( conf_net_cut <= 0 )) && return 0

    (( verbose )) && echo "++++++++++++++++++ cut network on $host_list"

    declare -A -g state_net_cut
    local host
    for host in $host_list; do
	state_net_cut[$host]=1
    done

    local rule_src="-p tcp --sport $conf_net_ports -j DROP"
    local rule_dst="-p tcp --dport $conf_net_ports -j DROP"
    remote_add "$host_list" "iptables -A INPUT $rule_src && iptables -A INPUT $rule_dst && iptables -A OUTPUT $rule_src && iptables -A OUTPUT $rule_dst || exit \$?"
    remote_wait
}

function IMPACT_net_cut_stop
{
    local host_list="${1:-$const_host_list}"

    (( conf_net_cut <= 0 )) && return 0

    (( verbose )) && echo "++++++++++++++++++ restore network on $host_list"

    declare -A -g state_net_cut
    local host
    for host in $host_list; do
	state_net_cut[$host]=0
    done

    remote_add "$host_list" "iptables -F"
    cluster_wait
}

