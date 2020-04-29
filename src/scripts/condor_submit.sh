#!/bin/bash
#
# 	File:     condor_submit.sh
# 	Author:   Giuseppe Fiorentino (giuseppe.fiorentino@mi.infn.it)
# 	Email:    giuseppe.fiorentino@mi.infn.it
#
# 	Revision history:
# 	08-Aug-2006: Original release
#       03-Apr-2007: Merged changes by Matt Farrellee (Condor) 
#       27-Oct-2009: Added support for 'local' requirements file.
#
# 	Description:
#   	Submission script for Condor, to be invoked by blahpd server.
#   	Usage:
#  	condor_submit.sh -c <command> [-i <stdin>] [-o <stdout>] [-e <stderr>] [-w working dir] [-- command's arguments]
#
# Copyright (c) Members of the EGEE Collaboration. 2004. 
# See http://www.eu-egee.org/partners/ for details on the copyright
# holders.  
# 
# Licensed under the Apache License, Version 2.0 (the "License"); 
# you may not use this file except in compliance with the License. 
# You may obtain a copy of the License at 
# 
#     http://www.apache.org/licenses/LICENSE-2.0 
# 
# Unless required by applicable law or agreed to in writing, software 
# distributed under the License is distributed on an "AS IS" BASIS, 
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. 
# See the License for the specific language governing permissions and 
# limitations under the License.
#

. `dirname $0`/blah_common_submit_functions.sh

original_args="$@"
# Note: -s (stage command) s ignored as it is not relevant for Condor.

# script debug flag: currently unused
bls_opt_debug=no

# number of MPI nodes: interpretted as a core count for vanilla universe
bls_opt_mpinodes=1

# Name of local requirements file: currently unused
bls_opt_req_file=""



bls_parse_submit_options "$@"

bls_setup_all_files

bls_test_input_files


##############################################################
# Create submit file
###############################################################

# set in bls_setup_all_files
submit_file=$bls_tmp_file


if [ ! -z "$bls_opt_inputflstring" ] ; then
    i=0
    for file in `cat $bls_opt_inputflstring`; do
	input_files[$i]=$file
	i=$((i+1))
    done
fi

if [ ! -z "$bls_opt_outputflstring" ] ; then
    i=0
    for file in `cat $bls_opt_outputflstring`; do
	output_files[$i]=$file
	i=$((i+1))
    done
fi

if [ ! -z "$remaps" ] ; then
    i=0
    for file in `cat $remaps`; do
	remap_files[$i]=$file
	i=$((i+1))
    done
fi

if [ ${#input_files[@]} -gt 0 ] ; then
    transfer_input_files="transfer_input_files=${input_files[0]}"
    for ((i=1; i < ${#input_files[@]}; i=$((i+1)))) ; do
	transfer_input_files="$transfer_input_files,${input_files[$i]}"
    done
fi

if [ ${#output_files[@]} -gt 0 ] ; then
    transfer_output_files="transfer_output_files=${output_files[0]}"
    for ((i=1; i < ${#output_files[@]}; i=$((i+1)))) ; do
	transfer_output_files="$transfer_output_files,${output_files[$i]}"
    done
fi

if [ ${#remap_files[@]} -gt 0 ] ; then
    if [ ! -z "${remap_files[0]}" ] ; then
	map=${remap_files[0]}
    else
	map=${output_files[0]}
    fi
    transfer_output_remaps="transfer_output_remaps=\"${output_files[0]}=$map"
    for ((i=1; i < ${#remap_files[@]}; i=$((i+1)))) ; do
	if [ ! -z "${remap_files[0]}" ] ; then
	    map=${remap_files[$i]}
	else
	    map=${output_files[$i]}
	fi
	transfer_output_remaps="$transfer_output_remaps;${output_files[$i]}=$map"
    done
    transfer_output_remaps="$transfer_output_remaps\""
fi

# Convert input environment (old Condor or shell format as dictated by 
# input args):

submit_file_environment="#"

if [ "x$environment" != "x" ] ; then
# Input format is suitable for bourne shell style assignment. Convert to
# new condor format to avoid errors  when things like LS_COLORS (which 
# has semicolons in it) get captured
    eval "env_array=($environment)"
    dq='"'
    sq="'"
    # escape single-quote and double-quote characters (by doubling them)
    env_array=("${env_array[@]//$sq/$sq$sq}")
    env_array=("${env_array[@]//$dq/$dq$dq}")
    # map key=val -> key='val'
    env_array=("${env_array[@]/=/=$sq}")
    env_array=("${env_array[@]/%/$sq}")
    submit_file_environment="environment = \"${env_array[*]}\""
else
    if [ "x$envir" != "x" ] ; then
# Old Condor format (no double quotes in submit file)
        submit_file_environment="environment = $envir"
    fi
fi

### This appears to only be necessary if Condor is passing arguments
### with the "new_esc_format"
# # NOTE: The arguments we are given are specially escaped for a shell,
# # so to get them back into Condor format we need to remove all the
# # extra quotes. We do this by replacing '" "' with ' ' and stripping
# # the leading and trailing "s.
if [[ $arguments = '"'*'"' ]]; then
  arguments=${arguments//'" "'/ }
  arguments=${arguments/#'"'}
  arguments=${arguments/%'"'}
fi

cat > $submit_file << EOF
universe = vanilla
executable = $command
EOF

if [ "x$proxy_file" != "x" ]
then
  echo "x509userproxy = $proxy_file" >> $submit_file
fi

if [ "x$req_mem" != "x" ]
then
  echo "request_memory = $req_mem" >> $submit_file
fi

if [ "x$runtime" != "x" ]
then
  echo "periodic_remove = JobStatus == 2 && time() - JobCurrentStartExecutingDate > $runtime" >> $submit_file
fi

cat >> $submit_file << EOF
request_cpus = $bls_opt_mpinodes
# We insist on new style quoting in Condor
arguments = $arguments
input = $stdin
output = $stdout
error = $stderr
$transfer_input_files
$transfer_output_files
$transfer_output_remaps
when_to_transfer_output = on_exit
should_transfer_files = yes
notification = error
$submit_file_environment
# Hang around for 1 day (86400 seconds) ?
# Hang around for 30 minutes (1800 seconds) ?
leave_in_queue = JobStatus == 4 && (CompletionDate =?= UNDEFINED || CompletionDate == 0 || ((CurrentTime - CompletionDate) < 1800))
EOF


#local batch system-specific file output must be added to the submit file
bls_local_submit_attributes_file=${blah_libexec_directory}/condor_local_submit_attributes.sh

bls_set_up_local_and_extra_args

echo "queue 1" >> $submit_file

###############################################################
# Perform submission
###############################################################

# Actual submission to condor to allow job enter the queue. The queue
# variable may be two parameters, separated by a space. If it is the
# first param is the name of the queue and the second is the name of
# the pool where the queue exists, i.e. a Collector's name.

echo $queue | grep "/" >&/dev/null
# If there is a "/" we need to split out the pool and queue
if [ "$?" == "0" ]; then
    pool=${queue#*/}
    queue=${queue%/*}
fi

if [ -z "$queue" ]; then
    target=""
else
    if [ -z "$pool" ]; then
	target="-name $queue"
    else
	target="-pool $pool -name $queue"
    fi
fi

now=`date +%s`
let now=$now-1

full_result=$($condor_binpath/condor_submit $target $submit_file)
return_code=$?

if [ "$return_code" == "0" ] ; then
    jobID=`echo $full_result | awk '{print $8}' | tr -d '.'`
    blahp_jobID="condor/$jobID/$queue/$pool"

    if [ "x$job_registry" != "x" ]; then
      ${blah_sbin_directory}/blah_job_registry_add "$blahp_jobID" "$jobID" 1 $now "$creamjobid" "$proxy_file" 0 "$proxy_subject"
    fi

    echo "BLAHP_JOBID_PREFIX$blahp_jobID"
else
    echo "Failed to submit"
    echo Error
fi

# Clean temporary files -- There only temp file is the one we submit
rm -f $submit_file

# Create a softlink to proxy file for proxy renewal - local renewal 
# of limited proxy only.

if [ "x$job_registry" == "x" ]; then
    if [ -r "$proxy_file" -a -f "$proxy_file" ] ; then
        [ -d "$proxy_dir" ] || mkdir $proxy_dir
        ln -s $proxy_file $proxy_dir/$jobID.proxy.norenew
    fi
fi

exit $return_code
