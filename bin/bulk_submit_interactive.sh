#!/bin/bash

#===============================================================================
# Copyright (c)  2014 Geoscience Australia
# All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#     * Redistributions of source code must retain the above copyright
#       notice, this list of conditions and the following disclaimer.
#     * Redistributions in binary form must reproduce the above copyright
#       notice, this list of conditions and the following disclaimer in the
#       documentation and/or other materials provided with the distribution.
#     * Neither Geoscience Australia nor the names of its contributors may be
#       used to endorse or promote products derived from this software
#       without specific prior written permission.
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY
# DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
# ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#===============================================================================

if [ $# -lt 4 ]
then
  echo "Usage: $0 <pbs_header> <python_script> <tile_selector> <output_dir> <additional_arguments>"
  echo "e.g: $0 my_header my_stacker_script.py canberra_tiles.txt ./test -s 20050101 -e 20051231"
  echo "N.B: <pbs_header> contains all of the comments required to set up a PBS job"
  echo "     <tile_selector> Defines the set of x/y tile indexes to process. Can be either a file path or a WKT string"
  echo "                     As a filepath it should point to a file containing space seperated x/y index pairs on a series of new lines"
  echo "                     As a WKT string it should define an EPSG:4326 geometry of which all intersecting tiles will be selected"
  exit 1
fi

# The tile list can be specified as either a file path or a WKT string
tile_list_cmd=''
if [ -e "$3" ]
then
  # File path is easy - just print the results
  tile_list_path="`readlink -f $3`"
  tile_list_cmd="cat \"$tile_list_path\""
else
  # WKT involves passing the string to cli_utilities.py
  tile_list_cmd="python cli_utilities.py get_tile_indexes \"$3\""
fi

pbs_header=`readlink -f $1`
python_script=`readlink -f $2`
output_dir=`readlink -f $4`

# Comment out the following line for interactive use
#PBS=1

shift 4
additional_arguments=$@

# Debug output
echo pbs_header=$pbs_header
echo python_script=$python_script
echo tile_list_cmd=$tile_list_cmd
echo output_dir=$output_dir
echo additional arguments: $additional_arguments

script_basename=$(basename ${python_script%.*})
mkdir -p ${output_dir}/jobs

# Iterate through tile index pairs in the output of tile_list_cmd
eval $tile_list_cmd | \
while read line
do
    x_index=`echo $line | cut -d' ' -f1`
    y_index=`echo $line | cut -d' ' -f2`

    echo Running ${python_script} on tile $x_index $y_index

    tile_output_path=${output_dir}/${x_index}_${y_index}
    tile_script_path=${output_dir}/jobs/${script_basename}_${x_index}_${y_index}.sh
    tile_stdout_log=${output_dir}/jobs/${script_basename}_${x_index}_${y_index}.log
    tile_stderr_log=${output_dir}/jobs/${script_basename}_${x_index}_${y_index}.err

    # Copy pbs_header file to script
    cp -f ${pbs_header} ${tile_script_path}

    # Append new python line
    echo "mkdir -p ${tile_output_path}
python ${python_script} -x ${x_index} -y ${y_index} -o ${tile_output_path} ${additional_arguments}" \
>> ${tile_script_path}

    if [ "$PBS" != "" ]
    then
        # The following lines are for submitting jobs on the NCI PBS system
        echo Submitting ${tile_script_path}
        #qsub -o ${tile_stdout_log} -e ${tile_stderr_log} ${tile_script_path}
        pushd ${output_dir}/jobs
        qsub ${tile_script_path} # Write output to default PBS log fliles
    else
        # The following lines are for running background jobs on the training VM
        echo Background executing ${tile_script_path}
        chmod 755 ${tile_script_path}
        ${tile_script_path} >${tile_stdout_log} 2>${tile_stderr_log} &
    fi

done
