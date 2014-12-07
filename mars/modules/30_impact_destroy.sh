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

# 0 = no destruction
# 1 = destroy a secondary
# 2 = destroy the primary
conf_destroy_mode="${conf_destroy_mode:-0}"

check_install_list="$check_install_list wipe"

function IMPACT_destroy_start
{
    (( conf_destroy_mode <= 0 )) && return 0

    local host_list
    local pause_list
    declare -A -g state_load
    declare -A -g state_net_cut

    if (( conf_destroy_mode >= 2 )); then
	host_list="${1:-$state_primary}"
	pause_list="${2:-$(list_minus "$state_secondary_list" "$state_bad_list")}"
    else
	host_list="${1:-$(select_first "$(list_minus "$state_secondary_list" "$state_bad_list")")}"
	pause_list="${2:-$host_list}"
    fi

    [[ "$host_list" = "" ]] && return 0
    remote_wait
    (( verbose )) && echo "++++++++++++++++++ starting logfile destroy at $host_list"

    local lv
    if [[ "$pause_list" != "" ]]; then
	(( verbose )) && echo "++++++ pausing replay at $pause_list"
	remote_add "$pause_list" "$marsadm pause-replay all || exit \$?"
	remote_wait
	if (( !state_net_cut[$state_primary] && state_load[$state_primary] )); then
	    (( verbose )) && echo "++++++ wait until more data arrived at $pause_list"
	    for lv in $(_get_lv_list); do
		remote_add "$pause_list" "$marsadm view-replay-rest $lv || exit \$?"
		remote_wait "$pred_is_greater_4096"
	    done
	fi
	(( verbose )) && echo "++++++ pausing fetch at $pause_list"
	remote_add "$pause_list" "$marsadm pause-fetch all || exit \$?"
	remote_wait
	for lv in $(_get_lv_list); do
	    # wait until fetching has really stopped
	    remote_add "$pause_list" "$marsadm view-is-fetch $lv || exit \$?"
	    # FIXME MARS: lower timeout to reasonable value
	    remote_wait "$pred_is_0" 0 600
	done
	if (( state_load[$state_primary] )); then
	    (( verbose )) && echo "++++++ wait until primary $state_primary has produced more logfile data"
	    for lv in $(_get_lv_list); do
		if (( state_net_cut[$state_primary] )); then
		    # wait until the source has produced additional logfile data
		    remote_add "$state_primary" "$marsadm view-work-size $lv || exit \$?"
		    remote_wait "false" 1
		else
		    # wait until the destinations know that the source has produced additional logfile data
		    remote_add "$pause_list" "$marsadm view-fetch-rest $lv || exit \$?"
		    remote_wait "$pred_is_greater_4096"
		fi
	    done
	fi
    fi
    (( verbose )) && echo "++++++ destroying logfile at $host_list"
    remote_add "$host_list" "for res in /mars/resource-*; do wipe -f -F -Z -e -k -q -Q 1 \$(ls \$res/log-* | tail -1) || exit \$?; done"
    remote_start
    if [[ "$pause_list" != "" ]]; then
	remote_wait
	(( verbose )) && echo "++++++ resuming fetch at $pause_list"
	remote_add "$pause_list" "$marsadm resume-fetch all || exit \$?"
	remote_wait
	(( verbose )) && echo "++++++ resuming replay at $pause_list"
	remote_add "$pause_list" "$marsadm resume-replay all || exit \$?"
	remote_wait
	if (( !state_net_cut[$state_primary] && state_load[$state_primary] )); then
	    (( verbose )) && echo "++++++ wait until fetch works again at $pause_list"
	    for lv in $(_get_lv_list); do
		remote_add "$pause_list" "$marsadm view-is-fetch $lv || exit \$?"
		remote_wait "$pred_is_1"
	    done
	fi
    fi

    state_bad_list+=" $host_list"
    _update_state
}

function IMPACT_destroy_wait
{
    remote_wait
}

function IMPACT_destroy
{
    IMPACT_destroy_start
    IMPACT_destroy_wait
}
