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

error_abort="${error_abort:-1}"
verbose="${verbose:-1}"
timeout="${timeout:-60}"
tmp_base="${tmp_dir:-/tmp/test-suite-$$}"
tmp_dir_list+=" $tmp_base"
check_install_list="ssh scp rsync"

function _get_host_tmp
{
    local host="$1"
    local dir="$tmp_base/host-$host"
    mkdir -p "$dir"
    echo "$dir"
}

function remote_add
{
    local host_list="$1"
    local cmd="$2"
    local host
    for host in $host_list; do
	local tmp_dir="$(_get_host_tmp ${host#!})"
	if [[ "$host" =~ "!" ]]; then
	    # expect failure of the command
	    echo "if { $cmd; }; then echo \"Sorry, the command did not fail as expected.\" >> /dev/stderr; exit 1; else echo \"IGNORING expected failure \$?\" >> /dev/stderr; fi" >> $tmp_dir/input
	else
	    # normal case: the command is responsible for generating any failures
	    echo "$cmd" >> $tmp_dir/input
	fi
    done
}

function remote_reset
{
    local host_list="${1:-$const_host_list}"
    local host
    for host in $host_list; do
	local tmp_dir="$(_get_host_tmp $host)"
	: > $tmp_dir/input
    done
}

function remote_start
{
    local host_list="${1:-$const_host_list}"

    local host
    for host in $host_list; do
	local tmp_dir="$(_get_host_tmp $host)"
	[[ -s "$tmp_dir/input" ]] || continue
	mv $tmp_dir/input $tmp_dir/input.start
	: > $tmp_dir/input
	cat $tmp_dir/input.start >> $tmp_dir/input.log
	(
	    {
		echo "shopt nullglob > /dev/null"
		echo "set -o verbose > /dev/null"
		cat $tmp_dir/input.start
	    } | ssh "root@$host" "bash" > $tmp_dir/output 2>&1
	    rc="$?"
	    echo "$rc" > $tmp_dir/status
	) &
	touch $tmp_dir/started
    done
}

function remote_restart
{
    local host_list="${1:-$const_host_list}"

    local host
    for host in $host_list; do
	local tmp_dir="$(_get_host_tmp $host)"
	if [[ -s "$tmp_dir/input.start" ]]; then
	    if [[ -s "$tmp_dir/input" ]]; then
		echo "INTERNAL ERROR: cannot restart" >> /dev/stderr
		script_fail 1
	    fi
	    mv $tmp_dir/input.start $tmp_dir/input
	fi
    done
    remote_start "$host_list"
}

function _msg_host
{
    local host="$1"

    local tmp_dir="$(_get_host_tmp $host)"
    local rc="$(cat $tmp_dir/status)"
    if (( verbose >= 2 || rc )); then
	echo "+++ $rc > $host" >> /dev/stderr
	cat $tmp_dir/output >> /dev/stderr
	echo "+++ $rc = $host" >> /dev/stderr
    fi
    return $rc
}

function remote_wait
{
    local predicate="$1"
    local until_change="${2:-0}"
    local this_timeout="${3:-$timeout}"

    remote_start # this is idempotent

    if (( verbose >= 3 )); then
	if (( verbose >= 4 )); then
	    for host in $const_host_list; do
		local tmp_dir="$(_get_host_tmp $host)"
		[[ -s "$tmp_dir/input.start" ]] || continue
		echo "+++ input of $host:" >> /dev/stderr
		cat $tmp_dir/input.start >> /dev/stderr
	    done
	fi
	echo "+++ waiting for" $(ls -d $tmp_base/host-* | sed "s:^$tmp_base/host-::" | cut -d/ -f1) >> /dev/stderr
    fi

    wait

    local host
    local res=0
    local repeat_list="xxx"
    local time=$(date +%s)
    local do_break=0
    while [[ "$repeat_list" != "" ]]; do
	repeat_list=""
	res=0
	for host in $const_host_list; do
	    local tmp_dir="$(_get_host_tmp $host)"


	    [[ -r "$tmp_dir/started" ]] || continue
	    [[ -s "$tmp_dir/status" ]] || continue

	    if ! _msg_host "$host"; then
		(( res++ ))
	    fi
	    rm -f $tmp_dir/started

	    grep "^COMPARE" < $tmp_dir/output > $tmp_dir/COMPARE
	    eval $(grep "^[a-z_0-9]\+=" < $tmp_dir/output)

	    if [[ "$predicate" != "" ]]; then
		if eval $predicate < $tmp_dir/output > $tmp_dir/predicate_output 2>&1 ; then
		    (( verbose >= 2 )) && echo "predicate '$predicate' true" >> /dev/stderr
		else
		    (( verbose >= 2 )) && echo "predicate '$predicate' false" >> /dev/stderr
		    repeat_list="$repeat_list $host"
		fi
		if (( verbose >= 3 )) && [[ -s $tmp_dir/predicate_output ]]; then
		    echo "predicate output:" >> /dev/stderr
		    cat $tmp_dir/predicate_output >> /dev/stderr
		fi
		mv $tmp_dir/output $tmp_dir/output.old
	    fi
	done
	(( do_break )) && break
	# wait until predicate is met everywhere or until timeout
	if [[ "$repeat_list" != "" ]]; then
	    sleep 1
	    remote_restart
	    wait

	    if (( until_change )); then
		# check whether all hosts report a change
		# (by comparison to the old output file)
		local no_change=0
		for host in $repeat_list; do
		    local tmp_dir="$(_get_host_tmp $host)"
		    if [[ -s "$tmp_dir/output.old" ]]; then
			if cmp "$tmp_dir/output.old" "$tmp_dir/output" > /dev/null 2>&1; then
			    (( no_change++ ))
			fi
		    else
			(( no_change++ ))
		    fi
		done
		if (( !no_change )); then
		    (( verbose >= 2 )) && echo "CHANGE detected" >> /dev/stderr
		    do_break=1
		fi
	    fi

	    local some_hanging=0
	    for host in $const_host_list; do
		local tmp_dir="$(_get_host_tmp $host)"
		[[ -s "$tmp_dir/status" ]] || continue
		if cmp $tmp_dir/output $tmp_dir/output.old >/dev/null 2>&1; then
		    (( some_hanging++ ))
		else # some progress has been made somewhere
		    time=$(date +%s)
		fi
	    done
	    (( verbose >= 5 )) && echo "[some_hanging='$some_hanging' time='$time']" >> /dev/stderr
	    if (( some_hanging && $(date +%s) > time + this_timeout )); then
		echo "TIMEOUT $this_timeout: predicate '$predicate' did not succeed" >> /dev/stderr
		for host in $repeat_list; do
		    _msg_host "$host"
		done
		fail -1
	    fi
	fi
    done
    # compare relevant parts of the output
    local old_file=""
    for host in $const_host_list; do
	local tmp_dir="$(_get_host_tmp $host)"
	local file="$tmp_dir/COMPARE"
	if [[ -s "$file" ]]; then
	    if [[ -s "$old_file" ]]; then
		(( verbose >= 3 )) && echo "comparing $old_file $file" >> /dev/stderr
		if cmp "$old_file" "$file"; then
		    echo "CHECKSUM OK" >> /dev/stderr
		else
		    echo "CHECKSUM MISMATCH" >> /dev/stderr
		    res=1
		fi
	    fi
	    old_file="$file"
	fi
    done
    # remove remains
    for host in $const_host_list; do
	local tmp_dir="$(_get_host_tmp $host)"
	rm -rf $tmp_dir
    done
    (( res && error_abort )) && fail $res
    return $res
}

script_count=0
function remote_script_add
{
    local host_list="$1" ; shift
    local do_background="${1:-0}" ; shift
    local suffix="${1:-script-$(( script_count++ ))}" ; shift

    local script_name="MARS-$suffix.sh"

    remote_add "$host_list" ": > $script_name || exit \$?"
    remote_add "$host_list" "cat >> $script_name <<EOF || exit \$?"
    remote_add "$host_list" "#!/bin/bash"
    remote_add "$host_list" "set -o verbose"

    local line
    for line in "$@"; do
	remote_add "$host_list" "$line"
    done

    local start_cmd
    if (( do_background )); then
	remote_add "$host_list" "wait"
	remote_add "$host_list" "echo DONE $script_name"
	start_cmd="./$script_name > output-$script_name 2>&1 &"
    else
	start_cmd="./$script_name 2>&1 | tee output-$script_name"
    fi

    remote_add "$host_list" "EOF"
    remote_add "$host_list" "chmod +x $script_name || exit \$?"
    remote_add "$host_list" "$start_cmd"
}

function remote_check_installed
{
    local host_list="${1:-$const_host_list}"

    remote_add "$host_list" "for i in $check_install_list; do which \$i || exit \$?; done"
    remote_wait
}

hooks_main_postmodules+=" remote_check_installed"