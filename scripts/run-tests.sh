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

# basic variables
fail_abort="${fail_abort:-0}"
resume="${resume:-${restart:-0}}"
class="${class:-recommended}"
dry_run="${dry_run:-0}"
verbose_script="${verbose_script:-0}"
start_date="${start_date:-$(date +%Y%m%d_%H%M%S)}"
logfiles="${logfiles:-run}"
total_logfiles="${total_logfiles:-total-run}"

# hooks
hooks_main_preconf=""
hooks_main_premodules=""
hooks_main_postmodules=""
hooks_main_pretestcases=""
hooks_main_prefilter=""
hooks_main_posttestcases=""
hooks_main_finalize=""

hooks_testcase_skipped=""
hooks_testcase_preconf=""
hooks_testcase_runconf=""
hooks_testcase_prestart=""
hooks_testcase_poststart=""
hooks_testcase_ok=""
hooks_testcase_failed=""
hooks_testcase_scripterrors=""
hooks_testcase_finalize=""

# determine important directories
start_dir="$(pwd)"
script_dir="$(cd "$(dirname "$(which "$0")")"; pwd)"
base_dir="$(cd $script_dir/..; pwd)"
log_dir="${log_dir:-$start_dir}"

shopt nullglob > /dev/null
set -o pipefail > /dev/null

tmp_dir_list=""

# This indicates that a test has failed / succeeded
function fail
{
    local code="${1:--1}"

    if (( code )); then
	echo "FAILURE $code" >> /dev/stderr
	code=1
    else
	echo "SUCCESS" >> /dev/stderr
    fi
    rm -rf $tmp_dir_list
    exit $code
}

# This indicates an error in the test suite - not in the test (making a big difference)
function script_fail
{
    local code="${1:-1}"
    echo "SCRIPT FAILURE $code (${BASH_SOURCE[@]}) (${FUNCNAME[@]})" >> /dev/stderr
    rm -rf $tmp_dir_list
    exit 127
}

function run_hooks
{
    local hook_list="$1" ; shift

    local script
    for script in $hook_list; do
	(( verbose_script )) && echo "  Running hook '$sript'" >> /dev/stderr
	$script "$@" || script_fail $?
    done
}

setup_list=""
test_start_list=""
test_case_list=""
override_var_list=""
function _scan_args
{
    local par
    for par in "$@"; do
	if [[ "$par:" =~ ".setup:" ]]; then
	    setup_list+=" $par"
	elif [[ "$par:" =~ ".run.sh:" ]]; then
	    if [[ ":$par" =~ ":/" ]] || [[ ":$par" =~ ":~" ]]; then
		test_case_list+=" $par"
	    else
		test_case_list+=" $start_dir/$par"
	    fi
	elif [[ "$par" =~ "=" ]]; then
	    par="${par#--}"
	    local lhs="$(echo "$par" | cut -d= -f1)"
	    local rhs="$(echo "$par" | cut -d= -f2-)"
	    # use '€' as list separator => allow blanks & co at the rhs
	    override_var_list+="€${lhs//-/_}=\"${rhs}\""
	elif [[ ":$par" =~ ":--" ]]; then
	    par="${par#--}"
	    override_var_list+="€${par//-/_}=1"
	else
	    echo "unusable parameter '$par'" >> /dev/stderr
	    script_fail 1
	fi
    done
}
_scan_args "$@"

function _get_run_files
{
    (
	cd $start_dir && find -L . -name "*.run.sh" | grep -v "/common" | sort -u | sort -g | sed "s:^\.:$start_dir:"
    )
}

function _get_basic_files
{
    local start_permut=${1:-1}
    local nr_permut=${2:-$start_permut}
    if (( start_permut <= 0 )); then
	find $(pwd) -name "common*.run.sh"
	return 0
    fi
    (
	local cand="$(ls -d *.run.sh 2>/dev/null)"
	if [[ "$cand" != "" ]] && ! [[ "/$cand" =~ "/common" ]] ; then
	    echo "$(pwd)/$cand"
	fi
	# restart the counting in directories where common runfiles are residing
	if ls common*.run.sh > /dev/null 2>&1; then
	    nr_permut="$start_permut"
	fi
	local sub_permut="$nr_permut"
	local next_permut=$(( nr_permut - 1 ))
	local i
	for i in $(ls -d * 2>/dev/null); do
	    if [[ -d "$i/" ]] && ! [[ "/$i" =~ "/common" ]] && (( $(find -L $i -name "*.run.sh" | grep -v "/common" | wc -l) > 0 )); then
		if [[ "$i" =~ "variants" ]]; then
		    ( cd $i/ && _get_basic_files "$start_permut" "$nr_permut" )
		elif (( sub_permut >= 0 )); then
		    ( cd $i/ && _get_basic_files "$start_permut" "$sub_permut" )
		    sub_permut="$next_permut"
		fi
	    fi
	done
    )
}

function _get_path_list
{
    local path="${1}"
    local stop_dir="${2:-$(cd $base_dir/..; pwd)}"

    local res="$path"
    local too_much=100
    while [[ "$path" =~ "/" ]]; do
	path="${path%/*}"
	[[ "${stop_dir}" =~ "$path" ]] && break
	res="$path $res"
	(( too_much-- <= 0 )) && script_fail 1
    done
    echo "${res% }"
}

function _source_files
{
    local dir_list="$1"
    local pattern="$2"

    local dir
    for dir in $dir_list; do
	(( verbose_script )) && echo "Checking directory $dir for '$pattern'" >> /dev/stderr
	local src
	local src_list="$(eval ls -v $dir/$pattern 2>/dev/null)"
	for src in $src_list; do
	    (( verbose_script )) && echo "  Sourcing $src" >> /dev/stderr
	    . $src || script_fail $?
	done
    done
}

function source_files
{
    local dir="$1"
    local stop_dir="${2:-$(cd $base_dir/..; pwd)}"
    local pattern="$3"

    _source_files "$(_get_path_list "$dir" "$stop_dir")" "$pattern"
}

# check that no preconf files are in subdirs
if [[ "$(find -L $(ls -d $start_dir/*/ 2>/dev/null) -name "*.preconf")" != "" ]]; then
    echo "Sorry, there are *.preconf files in some subdirectories of $start_dir" >> /dev/stderr
    echo "Please go to an appropriate subdir and start the testsuite there." >> /dev/stderr
    script_fail 1
fi

function _override_vars
{
    echo "Overriding variables from the command line:"
    local list="$1"
    local i
    for i in ${override_var_list#€}; do
	echo "  $i"
	eval "$i"
    done
}

##################################################################

# actions callable by *.class

oldname_present=0
function OLDNAME
{
    if (( verbose_script )); then
	echo "OLDNAME $@" >> /dev/stderr
	(( oldname_present++ ))
    fi
}

function SELECT
{
    local i
    local pattern
    for i in $test_start_list; do
	local ok=1
	for pattern; do
	    if ! [[ "$i" =~ "$pattern" ]]; then
		ok=0
		break
	    fi
	done
	if (( ok )) && ! [[ " $test_case_list " =~ " $i " ]]; then
	    (( oldname_present )) && echo "  -> $i" >> /dev/stderr
	    test_case_list+=" $i"
	fi
    done
}

function SELECT_BASIC
{
    local start_permut=${1:-1}
    test_case_list="$(cd $start_dir && _get_basic_files "$start_permut")"
}

function REMOVE
{
    local i
    local pattern
    local new_list=""
    for i in $test_case_list; do
	local ok=1
	for pattern; do
	    if ! [[ "$i" =~ "$pattern" ]]; then
		ok=0
		break
	    fi
	done
	if (( ok )); then
	    (( oldname_present )) && echo "  XX $i" >> /dev/stderr
	else
	    new_list+=" $i"
	fi
    done
    test_case_list="${new_list# }"
}

###############################################################

# start running

function main
{
    echo "=============================================================================="
    date

    if (( verbose_script >= 2 )); then
	echo "start_dir=$start_dir"
	echo "script_dir=$script_dir"
	echo "base_dir=$base_dir"
    fi

    # source all relevant input files

    run_hooks "$hooks_main_preconf"
    source_files "$start_dir" "" "{conf/,}*.preconf"
    local param
    for param in $setup_list; do
	source_files "$start_dir" "" "{conf/,}$param"
    done
    if [[ "$override_var_list" != "" ]]; then
	IFS='€' _override_vars
    fi
    run_hooks "$hooks_main_premodules"
    source_files "$start_dir" "" "modules/[0-9]*.sh"
    run_hooks "$hooks_main_postmodules"
    source_files "$start_dir" "" "{conf/,}*.runconf"
    if [[ "$override_var_list" != "" ]]; then
	IFS='€' _override_vars
    fi

    # determine test cases

    local total_count
    if [[ "$test_case_list" = "" ]]; then
	(( verbose_script )) && echo "Find all tests in '$start_dir'" >> /dev/stderr
	test_start_list="$(_get_run_files)"
	run_hooks "$hooks_main_pretestcases"
	total_count="$(echo "$test_start_list" | wc -w)"
	(( verbose_script )) && echo "  found $total_count test cases." >> /dev/stderr
	if [[ "$class" = "" ]]; then
	    (( verbose_script )) && echo "No filter class given, using the full set of tests" >> /dev/stderr
	    test_case_list="$test_start_list"
	else
	    (( verbose_script )) && echo "Filtering classes '$class'" >> /dev/stderr
	    run_hooks "$hooks_main_prefilter"
	    local this_class
	    for this_class in $class; do
		source_files "$start_dir" "" "{conf/,}$this_class.class"
	    done
	fi
    else
	total_count="$(echo "$test_case_list" | wc -w)"
	(( verbose_script )) && echo "You supplied $total_count test cases on the command line." >> /dev/stderr
    fi

    run_hooks "$hooks_main_posttestcases"

    local case_count="$(echo "$test_case_list" | wc -w)"
    echo "======= using $case_count / $total_count test cases." >> /dev/stderr

    # run test cases

    local start_count=0
    local skipped_count=0
    local ok_count=0
    local fail_count=0
    local script_fail_count=0
    local rc=0
    for test_case in $test_case_list; do
	local test_dir="$(dirname $test_case)"
	local test_script="$(basename $test_case)"
	local test_dir_as_file="${test_dir/$start_dir/}"
	test_dir_as_file="${test_dir_as_file//\//_}"
	test_dir_as_file="${test_dir_as_file//_variants/}"
	test_dir_as_file="${test_dir_as_file#_}"
	if (( resume )); then
	    local check_file="$(ls -v $log_dir/$logfiles-*.$test_dir_as_file.log | tail -1)"
	    if [[ -r "$check_file" ]] && grep -q "^THIS TEST OK" < "$check_file"; then
		echo "Skipping $test_dir/$test_script"
		(( skipped_count++ ))
		run_hooks "$hooks_testcase_skipped" "$test_case"
		continue;
	    fi
	fi
	(( start_count++ ))
	(
	    echo ""
	    echo "=============================================================================="
	    cd $test_dir
	    echo "$test_case"
	    echo "====== $start_count $(date)"
	    run_hooks "$hooks_testcase_preconf" "$test_case"
	    source_files "$test_dir" "$start_dir" "{conf/,}*.runconf" || exit $?
	    run_hooks "$hooks_testcase_runconf" "$test_case"
	    if [[ "$override_var_list" != "" ]]; then
		IFS='€' _override_vars
	    fi
	    rc=0
	    if (( dry_run )); then
		echo "  (--dry-run) Would start $test_dir/$test_script"
	    else
		echo ""
		run_hooks "$hooks_testcase_prestart" "$test_case"
		if (( verbose )); then
		    echo "CURRENTLY SKIPPED: $skipped_count"
		    echo "CURRENTLY     BAD: $script_fail_count"
		    echo "CURRENTLY  FAILED: $fail_count"
		    echo "CURRENTLY      OK: $ok_count / $start_count"
		    echo ""
		fi
		. $test_script
		rc="$?"
		run_hooks "$hooks_testcase_poststart" "$test_case"
		echo "====== $start_count $(date) rc=$rc"
		echo "$test_case"
		if (( rc )); then
		    if (( rc == 127 )); then
			echo "SCRIPT HAS ERRORS $test_case"
			run_hooks "$hooks_testcase_scripterrors" "$test_case"
		    else
			echo "THIS TEST FAILED $test_case"
			run_hooks "$hooks_testcase_failed" "$test_case"
		    fi
		    (( fail_abort )) && exit $rc
		else
		    echo "THIS TEST OK $test_case"
		    run_hooks "$hooks_testcase_ok" "$test_case"
		fi
		run_hooks "$hooks_testcase_finalize" "$test_case"
	    fi
	) 2>&1 | tee "$log_dir/$logfiles-$start_date.$test_dir_as_file.log"
	rc="$?"
	if (( rc )); then
	    if (( rc == 127 )); then
		(( script_fail_count++ ))
	    else
		(( fail_count++ ))
	    fi
	    (( fail_abort )) && break
	    sleep 1
	else
	    (( ok_count++ ))
	fi
	if (( verbose )); then
	    echo "CURRENTLY SKIPPED: $skipped_count"
	    echo "CURRENTLY     BAD: $script_fail_count"
	    echo "CURRENTLY  FAILED: $fail_count"
	    echo "CURRENTLY      OK: $ok_count / $start_count"
	fi
    done
    
    run_hooks "$hooks_main_finalize"

    echo "=============================================================================="
    date
    if (( !dry_run )); then
	echo "TESTCASES SKIPPED: $skipped_count"
	echo "TESTCASES STARTED: $start_count"
	echo "TESTCASES     BAD: $script_fail_count"
	echo "TESTS      FAILED: $fail_count"
	echo "TESTS          OK: $ok_count / $start_count"
    fi

    echo "started $start_count / selected $case_count / available $total_count test cases."
    fail "$rc"
}

main 2>&1 | tee "$log_dir/$total_logfiles-$start_date.log"
