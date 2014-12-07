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

conf_switch_force=${conf_switch_force:-0}
conf_switch_back=${conf_switch_back:-0}
conf_switch_restart_load=${conf_switch_restart_load:-1}
conf_switch_check_fail=${conf_switch_check_fail:-1}
conf_silly_restart=${conf_silly_restart:-0}

conf_alternate_count=0

function SWITCH_start
{
    local new_primary="${1:-$(select_first "$state_secondary_list")}"
    remote_wait

    declare -A -g state_load
    declare -A -g state_fs_mounted

    local old_state_load="${state_load[$state_primary]}"
    (( verbose >= 2 )) && echo "state_load[$state_primary]=$old_state_load"

    # Check preconditions
    if (( !old_state_load )); then
	if (( conf_unload_enable > 0 )); then
	    echo "BAD CONFIG: Sorry, it makes no sense to use conf_unload_enable=$conf_unload_enable"
	    echo "when no load was started."
	    script_fail 1
	elif (( conf_destroy_mode >= 2 )); then
	    echo "BAD CONFIG: Sorry, it makes no sense to use conf_destroy_mode=$conf_destroy_mode"
	    echo "when no load was started."
	    echo "The defective logfile may have size 0, and it need not propagate"
	    echo "to secondaries at all. This makes no sense."
	    script_fail 1
	fi
    fi
    if (( conf_silly_restart )); then
	if (( conf_net_cut <= 0 )); then
	    echo "BAD CONFIG: Sorry, you cannot enable conf_silly_restart"
	    echo "when the network is OK. Silly operation of two primaries in parallel"
	    echo "CAN only work when both hosts cannot communicate with each other."
	    echo "Please disable conf_net_cut if you want to the SILLY tests."
	    script_fail 1
	elif (( conf_unload_enable != 1 )); then
	    echo "BAD CONFIG: Sorry, it makes no sense to enable conf_silly_restart"
	    echo "but to disable conf_unload_enable"
	    script_fail 1
	fi
    fi
    if (( conf_destroy_mode == 1 )); then
	echo "BAD CONFIG: Sorry, cannot handle destruction of a secondary in switch2primary."
	echo "Either use conf_destroy_mode=0 or conf_destroy_mode=2 here."
	echo "If you want to test whether a logfile destruction on a secondary"
	echo "can be successfully repaired, notice that no switching is necessary"
	echo "for achieving this."
	echo "Just logrotate and repair the damaged secondary via REPAIR and be happy."
	script_fail 1
    fi
    if (( conf_destroy_mode >= 2 )); then
	if (( conf_switch_force <= 0 )); then
	    echo "BAD CONFIG: Sorry, cannot destroy the original primary and then handover to another host."
	    echo "When conf_destroy_mode == 2 is enabeled, you must also"
	    echo "enable conf_switch_force (but not conf_switch_back)."
	    script_fail 1
	elif (( conf_switch_back > 0 )); then
	    echo "BAD CONFIG: Sorry, cannot destroy the original primary and then siwtch back to it."
	    echo "The combination conf_destroy_mode == 2 && conf_switch_back > 0 is illegal."
	    script_fail 1
	fi
    fi
    if (( conf_net_cut > 0 && conf_switch_force <= 0 )); then
	echo "BAD CONFIG: Sorry, handover is not possible when the network has failed."
	    script_fail 1
    fi

    # The impacts are conceptually orthogonal to ANY switch mode (handover or forcing)
    if (( conf_destroy_mode <= 0 )); then
	IMPACT_net_bottle_start
	IMPACT_logrotate
	IMPACT_net_cut_start
	IMPACT_unload
    else
	IMPACT_net_bottle_start
	IMPACT_net_cut_start
	IMPACT_destroy
	IMPACT_logrotate
	IMPACT_unload
    fi

    local lv

    # set new state variables
    state_primary_old="$state_primary"
    state_primary="$new_primary"
    _update_state

    (( verbose )) && echo "++++++++++++++++++ switch2primary $( (( conf_switch_force )) && echo FORCE) $state_primary_old -> $state_primary"

    if (( conf_switch_force )); then
	# Even forced switching cannot succeed when logfiles are damaged
	# and can propagate.
	if (( conf_destroy_mode >= 2 && conf_net_cut <= 0 )); then
	    # In this case, plain switching will fail.
	    # We check this, and then we enable a sloppy mode allowing to
	    # become primary even when logfiles are damaged.
	    if (( conf_switch_check_fail )); then
		(( verbose )) && echo "++++++ check that forced switching will fail at $state_primary because the old primary $state_primary_old has a destroyed logfile"
		remote_add "$state_primary" "$marsadm disconnect all || exit \$?"
		for lv in $(_get_lv_list); do
		    remote_add "!$state_primary" "$marsadm --timeout=$const_fail_timeout primary --force $lv"
		done
		remote_wait
	    fi
	    (( verbose )) && echo "++++++ allow becoming primary at $state_primary even when logfiles are damaged"
	    remote_add "$state_primary" "echo 1 > /proc/sys/mars/allow_primary_when_damaged || exit \$?"
	    remote_wait
	    (( verbose )) && echo "++++++ now forced switching at $state_primary must succeed"
	fi

	# Go into SPLIT BRAIN, deliberately....
	for lv in $(_get_lv_list); do
	    remote_add "$state_primary" "$marsadm disconnect $lv || exit \$?"
	    remote_add "$state_primary" "$marsadm primary --force $lv || exit \$?"
	done
	remote_wait

	if (( old_state_load )); then
	    (( verbose )) && echo "++++++ starting additional load at $state_primary"
	    for lv in $(_get_lv_list); do
		_SETUP_mount_start "$state_primary" "$lv"
	    done
	    _LOAD_start "$state_primary" 1
	    remote_wait
	fi

	IMPACT_logrotate
	IMPACT_unload

	# Somebody put a _wrong_ requirement on me that during split brain
	# both hosts must be FULLY operable.
	# This is conceptually WRONG because split brain must be always
	# resolved ASAP since it always creates DATA LOSS (at the time
	# of resolution).
	# There is absolutely no clue in restarting load on _both_ split-brain
	# nodes in parallel. It just increases the LOSS. Other secondaries
	# cannot follow it. It just creates _avoidable_ problems.
	# If you argue that the original resource could be split into 2
	# different resources by creating a new one out of the "lost"
	# version, then I answer that you should do that ASAP, and not by
	# indefinitely operating split-brain on a single resource in parallel.
	# The following is BAD SYSADMIN BEHAVIOUR.
	# But the test implements it anyway .... just to be sure that MARS
	# can cope even with EXTREMELY SILLY REQUIREMENTS(tm)
	if (( conf_silly_restart && conf_unload_enable == 1 )); then
	    (( verbose )) && echo "++++++ SILLY restarting load at both $state_primary_old and $state_primary during split brain (EXTREMELY SILLY)"
	    _SETUP_mount_stop
	    remote_add "$state_primary_old $state_primary" "$marsadm wait-umount all || exit \$?"
	    remote_wait
	    local host
	    for host in $state_primary_old $state_primary; do
		remote_add "$host" "$marsadm disconnect all || exit \$?"
		for lv in $(_get_lv_list); do
		    remote_add "$host" "$marsadm primary --force $lv || exit \$?"
		done
		remote_wait
		remote_add "$host" "$marsadm --timeout=$timeout view-wait-is-primary-on all || exit \$?"
		remote_wait
		for lv in $(_get_lv_list); do
		    _SETUP_mount_start "$host" "$lv"
		done
		_LOAD_start "$host" 1
		remote_wait
	    done
	    IMPACT_logrotate "$state_primary_old $state_primary"
	fi

	# Logically start recovery phase here.
	# The network must work again (if it was interrupted)

	IMPACT_net_cut_stop
	IMPACT_net_bottle_stop

	# Up to HERE we are in SPLIT BRAIN....
	# Starting from HERE we decide to repair the mess....

	# decide which to throw away....
	if (( conf_switch_back )); then
	    state_primary="$state_primary_old"
	else
	    state_primary="$state_primary"
	fi
	state_primary_old=""
	state_bad_list="$(list_minus "$const_host_list" "$state_primary")"
	_update_state

	if (( conf_switch_back || conf_unload_enable >= 2 || conf_silly_restart )); then
	    (( verbose )) && echo "++++++ switch designated primary back to $state_primary"
	    remote_add "$state_primary" "$marsadm disconnect all || exit \$?"
	    for lv in $(_get_lv_list); do
		remote_add "$state_primary" "$marsadm primary --force $lv || exit \$?"
	    done
	    remote_wait
	    # No, the device need not appear because there may be split brain
	    remote_add "$state_primary" "$marsadm --timeout=$timeout view-wait-is-primary-on all || echo IGNORE this"
	    remote_wait
	fi
	cluster_wait

	REPAIR

	if (( conf_switch_restart_load && old_state_load && !conf_switch_back && conf_repair_mode >= 3 )); then
	    (( verbose )) && echo "++++++ restarting load at $state_primary"
	    for lv in $(_get_lv_list); do
		_SETUP_mount_start "$state_primary" "$lv"
	    done
	    _LOAD_start "$state_primary" 1
	fi
    else # !conf_switch_force
	if (( conf_switch_check_fail && state_fs_mounted[$state_primary_old] )); then
	    (( verbose )) && echo "++++++ checking whether illegal handover attempt fails"
	    remote_add "!$state_primary" "$marsadm --timeout=$const_fail_timeout primary all"
	    remote_wait
	fi
	if (( old_state_load || state_fs_mounted[$state_primary_old] )); then
	    (( verbose )) && echo "++++++ stopping mounts"
	    _SETUP_mount_stop
	fi
        # check that old primary has flushed everything
	remote_add "$state_primary_old" "$marsadm view all"
	remote_wait "$pred_all_flushed"
	remote_add "$state_primary_old" "$marsadm wait-umount all || exit \$?"
	cluster_wait
	(( verbose )) && echo "++++++ handover $state_primary_old -> $state_primary"
	remote_add "$state_primary" "$marsadm primary all || exit \$?"
	remote_start
	if (( conf_switch_restart_load && old_state_load )); then
	    remote_wait
	    (( verbose )) && echo "++++++ restarting load at $state_primary"
	    for lv in $(_get_lv_list); do
		_SETUP_mount_start "$state_primary" "$lv"
	    done
	    _LOAD_start "$state_primary" 1
	fi
	REPAIR
    fi
    IMPACT_net_bottle_stop
}

function SWITCH_wait
{
    remote_wait
}

function SWITCH
{
    local new_primary="${1:-$(select_first "$state_secondary_list")}"
    SWITCH_start "$new_primary"
    SWITCH_wait
}

function ALTERNATE
{
    local new_primary="${1:-$(select_first "$state_secondary_list")}"

    # temporarily use different config options
    (
	conf_switch_force=0
	conf_switch_back=0
	conf_switch_check_fail=0
	conf_switch_restart_load=0
	conf_silly_restart=0
	conf_net_cut=0
	conf_destroy_mode=0
	conf_logrotate_count="${conf_alternate_count:-0}"
	conf_unload_enable=0
	LOAD_start
	SWITCH "$new_primary"
	LOAD_stop
    ) || exit $?
    state_primary="$new_primary"
    _update_state
    SETUP_mount_start
    SETUP_fs_wait
    LOAD_start
}