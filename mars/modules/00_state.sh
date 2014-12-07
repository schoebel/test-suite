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

function select_first
{
    local list="$1"
    echo "${list/ */}"
}

function select_last
{
    local list="$1"
    echo "${list/* /}"
}

################### state variables

const_host_list="${const_host_list:-test1 test2 test3}"

state_primary="${state_primary:-$(select_first "$const_host_list")}"
state_primary_old=""
state_bad_list=""
state_secondary_list=""

#########################

function list_intersect
{
    local list_a="$1"
    local list_b="$2"
    local res=""
    local i
    for i in $list_a; do
	[[ " $list_b " =~ " $i " ]] && res="$res $i"
    done
    res="${res/# /}"
    echo "$res"
}

function list_minus
{
    local list_a="$1"
    local list_b="$2"
    local i
    for i in $list_b; do
	list_a="${list_a/$i/}"
	list_a="${list_a/  / }"
    done
    list_a="${list_a/# /}"
    list_a="${list_a/% /}"
    echo "$list_a"
}

function list_reduce
{
    local list="$1"
    local max="${2:-2}"
    local i
    local count=0
    for i in $list; do
	(( count >= max )) && break
	(( count > 0 )) && echo -n " "
	echo -n "$i"
	(( count++ ))
    done
}

function dump_vars
{
    local var_list="$1"

    local var
    for var in $var_list; do
	echo "$var='$(eval echo \$$var)'"
    done
}

function reduce_hosts
{
    local max="${1:-2}"
    local old="$const_host_list"
    const_host_list="$(list_reduce "$const_host_list" "$max")"
    [[ "$const_host_list" != "$old" ]] && (( verbose )) && echo "++++++++++++++++++ reducing host list to $const_host_list"
}

function _update_state
{
    # elimintate wrong members
    state_bad_list="$(list_intersect "$const_host_list" "$state_bad_list")"
    state_primary="$(list_intersect "$const_host_list" "$state_primary")"
    state_primary="$(list_minus "$state_primary" "$state_bad_list")"
    # always select a first primary
    state_primary="${state_primary:-$(select_first "$const_host_list")}"
    # put all the rest into secondary_list
    state_secondary_list="$(list_minus "$const_host_list" "$state_primary $state_bad_list")"
}

_update_state

if (( verbose_script )); then
    dump_vars "const_host_list state_primary state_bad_list state_secondary_list"
fi

################### old test code
return 0

select_first "$const_host_list"
select_last "$const_host_list"

list_intersect "$const_host_list" "v2"
list_intersect "$const_host_list" "v1 v3"

list_minus "$const_host_list" "v2"
list_minus "$const_host_list" "$(select_first "$const_host_list")"

