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

conf_logrotate_count="${conf_logrotate_count:-0}"
conf_logrotate_sleep="${conf_logrotate_sleep:-4}"

function _logrotate_add
{
    local host_list="$1"
    local do_background="${2:-0}"
    local count="${3:-$conf_logrotate_count}"
    local sleep_time="${4:-$conf_logrotate_sleep}"

    local -a args
    local i=0
    while (( count-- > 0 )); do
	args[$(( i++ ))]="marsadm log-rotate all"
	args[$(( i++ ))]="marsadm log-delete-all all"
	args[$(( i++ ))]="sleep $sleep_time"
    done
    remote_script_add "$host_list" "$do_background" "logrotate" "${args[@]}"
}

function IMPACT_logrotate_start
{
    local host_list="${1:-$state_primary}"
    local do_background="${2:-1}"
    local count="${3:-$conf_logrotate_count}"
    local sleep_time="${4:-$conf_logrotate_sleep}"

    (( count <= 0 )) && return 0
    remote_wait
    (( verbose )) && echo "++++++++++++++++++ starting logrotates at $host_list"
    _logrotate_add "$host_list" "$do_background" "$count" "$sleep_time"
    remote_start
}

function IMPACT_logrotate_stop
{
    local host_list="${1:-$state_primary}"

    remote_wait
    remote_add "$host_list" "while killall -r MARS-logrotate; do sleep 1; done"
    remote_wait
}

function IMPACT_logrotate
{
    local host_list="${1:-$state_primary_old $state_primary}"
    local count="${3:-$conf_logrotate_count}"
    local sleep_time="${4:-$conf_logrotate_sleep}"

    (( count <= 0 )) && return 0
    remote_wait
    (( verbose )) && echo "++++++++++++++++++ doing $count logrotates at $host_list"
    _logrotate_add "$host_list" 0 "$count" "$sleep_time"
    remote_wait
}
