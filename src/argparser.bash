#!/bin/bash
##
# argparser – command line argument parser library
# 
# Copyright © 2013  Mattias Andrée (maandree@member.fsf.org)
# 
# This library is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this library.  If not, see <http://www.gnu.org/licenses/>.
##



# I could make maps or Bash, but I really prefer not to, therefore
# /tmp/argparser_$$ is used instead to let the fs constructor sets.



# :int  Option takes no arguments
args_ARGUMENTLESS=0

# :int  Option takes one argument per instance
args_ARGUMENTED=1

# :int  Option consumes all following arguments
args_VARIADIC=2



# Constructor.
# The short description is printed on same line as the program name
# 
# @param  $1:str  Short, single-line, description of the program
# @param  $2:str  Formated, multi-line, usage text, empty for none
# @param  $3:str  Long, multi-line, description of the program, empty for none
# @param  $4:str  The name of the program, empty for automatic
# @param  $5:str  Output channel, by fd
function args_init
{
    test "$TERM" = linux
    args_linuxvt=$?
    args_program="$4"
    if [ "$args_program" = "" ]; then
        args_program="$0"
    fi
    args_description="$1"
    args_usage="$2"
    args_longdescription="$3"
    args_options=()
    args_opts_alts=()
    args_opts="/tmp/argparser_$$/opts"
    args_optmap="/tmp/argparser_$$/optmap"
    mkdir -p "${args_opts}"
    mkdir -p "${args_optmap}"
    args_out="$5"
    if [ "$args_out" = "" ]; then
        args_out="1"
    fi
    args_out="$(realpath "/proc/$$/fd/${args_out}")"
    args_files=()
}


# Disposes of resources, you really should be doing this when you are done with this module
# 
# @param  $1:int  The ID of process that alloceted the resources, empty for the current process
function args_dispose
{
    local pid=$1
    if [ "$pid" = "" ]; then
        pid=$$
    fi
    rm -r "/tmp/argparser_${pid}"
}


# Gets the name of the parent process
# 
# @param   $1:int  The number of parents to walk, 0 for self, and 1 for direct parent
# @return  :str    The name of the parent process, empty if not found
# @exit            0 of success, 1 if not found
function args_parent_name
{
    local pid=$$ lvl=$1 found=0 line arg
    while (( $lvl > 1 )) && [ $found = 0 ]; do
	while read line; do
	    if [ "${line:5}" = "PPid:" ]; then
		line="${line:5}"
		line="${line/$(echo -e \\t)/}"
		pid="${line/ /}"
		(( lvl-- ))
		found=1
		break
	    fi
	done < "/proc/${pid}/cmdline"
    done
    if [ $found = 0 ]; then
	return 1
    fi
    if [ -e "/proc/${pid}/cmdline" ]; then
	for arg in "$(cat /proc/${pid}/cmdline | sed -e 's/\x00/\n/g')" ; do
	    echo "$arg"
	    return 0
	done
    fi
    return 1
}


# Maps up options that are alternatives to the first alternative for each option
function args_support_alternatives
{
    local alt
    for alt in "$(ls "${args_optmap}")"; do
	ln -s "${args_opts}/$(head -n 1 < "${args_optmap}/${alt}")" "${args_opts}/${alt}"
    done
}


# Checks for option conflicts
# 
# @param   $@:(str)  Exclusive options
# @exit              Whether at most one exclusive option was used
function args_test_exclusiveness
{
    local used used_use used_std opt msg i=0 n
    used=()
    opts_use=()
    opts_std=()
    
    for opt in "$@"; do
	echo "$opt"
    done > "/tmp/argparser_$$/tmp"
    
    comm -12 <(ls "${args_opts}" | sort) <(cat "/tmp/argparser_$$/tmp" | sort) |
    while read opt; do
	if [ -e "${args_opts}/${opt}" ]; then
            opts_use+=( "${opt}" )
	    opts_std+=( "$(head -n 1 < ${args_optmap}/${opt})" )
	fi
    done
    
    rm "/tmp/argparser_$$/tmp"
    
    n=${#used[@]}
    if (( $n > 1 )); then
	msg="${args_program}: conflicting options:"
	while (( $i < $n )); do
	    if [ "${used_use[$i]}" = "${used_std[$i]}" ]; then
		msg="${msg} ${used_use[$i]}"
	    else
		msg="${msg} ${used_use[$i]}(${used_std[$i]})"
	    fi
	    (( i++ ))
	done
	echo "$msg" > "${args_out}"
	return 1
    fi
    return 0
}


# Checks for out of context option usage
# 
# @param   @:(str)  Allowed options
# @exit             Whether only allowed options was used
function args_test_allowed
{
    local opt msg std rc=0
    
    for opt in "$@"; do
	echo "$opt"
    done > "/tmp/argparser_$$/tmp"
    
    comm -23 <(ls "${args_opts}" | sort) <(cat "/tmp/argparser_$$/tmp" | sort) |
    while read opt; do
	if [ -e "${args_opts}/${opt}" ]; then
	    msg="${args_program}: option used out of context: ${opt}"
	    std="$(head -n 1 < "${args_optmap}/${opt}")"
	    if [ ! "${opt}" = "${std}" ]; then
		msg="${msg}(${std})"
	    fi
	    echo "$msg" > "${args_out}"
	    rc=1
	fi
    done
    
    rm "/tmp/argparser_$$/tmp"
    return $rc
}


# Checks the correctness of the number of used non-option arguments
# 
# @param  $1:int   The minimum number of files
# @param  $2:int?  The maximum number of files, empty for unlimited
# @exit            Whether the usage was correct
function args_test_files
{
    local min=$1 max=$2 n=${#args_files[@]}
    if [ "$max" = "" ]; then
	max=$n
    fi
    (( $min <= $n )) && (( $n <= $max ))
    return $?
}


# Add option that takes no arguments
# 
# @param  $1:int     The default argument's index
# @param  $2:str     Short description, use empty to hide the option
# @param  ...:(str)  Option names
function args_add_argumentless
{
    local default="$1" help="$2" std alts alt
    shift 2
    args_options+=( ${args_ARGUMENTLESS} "" "${help}" ${#args_opts_alts[@]} $# )
    args_opts_alts+=( "$@" )
    alts=( "$@" )
    std="${alts[$default]}"
    for alt in "${alts[@]}"; do
	echo "$std" > "${args_optmap}/${alt}"
	echo ${args_ARGUMENTLESS} >> "${args_optmap}/${alt}"
    done
}


# Add option that takes one argument
# 
# @param  $1:int     The default argument's index
# @param  $2:str     The name of the takes argument, one word
# @param  $3:str     Short description, use empty to hide the option
# @param  ...:(str)  Option names
function args_add_argumented
{
    local default="$1" arg="$2" help="$3" std alts alt
    shift 3
    if [ "${arg}" = "" ]; then
	arg="ARG"
    fi
    args_options+=( ${args_ARGUMENTED} "${arg}" "${help}" ${#args_opts_alts[@]} $# )
    args_opts_alts+=( "$@" )
    alts=( "$@" )
    std="${alts[$default]}"
    for alt in "${alts[@]}"; do
	echo "$std" > "${args_optmap}/${alt}"
	echo ${args_ARGUMENTED} >> "${args_optmap}/${alt}"
    done
}


# Add option that takes all following arguments
# 
# @param  $1:int     The default argument's index
# @param  $2:str     The name of the takes argument, one word
# @param  $3:str     Short description, use empty to hide the option
# @param  ...:(str)  Option names
function args_add_variadic
{
    local default="$1" arg="$2" help="$3" std alts alt
    shift 3
    if [ "${arg}" = "" ]; then
	arg="ARG"
    fi
    args_options+=( ${args_VARIADIC} "${arg}" "${help}" ${#args_opts_alts[@]} $# )
    args_opts_alts+=( "$@" )
    alts=( "$@" )
    std="${alts[$default]}"
    for alt in "${alts[@]}"; do
	echo "$std" > "${args_optmap}/${alt}"
	echo ${args_VARIADIC} >> "${args_optmap}/${alt}"
    done
}

