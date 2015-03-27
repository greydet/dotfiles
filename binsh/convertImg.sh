#!/bin/bash
#
# Copyright (C) 2013 Gonzague Reydet.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

usage()
{
cat << EOF
Uasge: $0 [-s SIZE] [-r ROTATION] [-o OUTPUT_DIR] [-f OUTPUT_FORMAT] FILE...
Resize the given image files.
EOF
}

outputDir=""
outputFormat=""
processOpts=""

while getopts "f:s:o:r:" ARGNAME; do
    case ${ARGNAME} in
        r)
            processOpts="${processOpts} -rotate ${OPTARG}"
            ;;
        s)
            processOpts="${processOpts} -resize ${OPTARG}"
            ;;
        o)
            outputDir=${OPTARG}
            ;;
        f)
            outputFormat=${OPTARG}
            ;;
        ?)
            usage
            exit 1
    esac
done

if [ "x${processOpts}" == "x" -a "x${outputFormat}" == "x" ]; then
    usage
    exit 1
fi

if [ $# -lt ${OPTIND} ]; then
    # No filename pattern given
    usage
    exit 1
fi

if [ "x${outputDir}" == "x" ]; then
    outputDir='out'
fi

mkdir -p ${outputDir}

doit()
{
    processOpts=$1
    outputFormat=$2
    outputDir=$3
    filename=$4

    if [ "x${outputFormat}" ==  "x" ]; then
        outFilename=`basename ${filename}`
    else
        outFilename=`basename ${filename%.*}.${outputFormat}`
    fi
    
    echo "Processing \"${filename}\""
    convert "${filename}" ${processOpts} "${outputDir}/${outFilename}"
    if [ $? != 0 ]; then
        exit 1
    fi
}
export -f doit

if parallel -V > /dev/null 2>&1; then
    # Doit in parallel
    parallel "doit \"${processOpts}\" \"${outputFormat}\" \"${outputDir}\"" ::: ${@:${OPTIND}}
else
    echo "parallel program not found. Conversion will be performed without parallelization."
    while [ ${OPTIND} -le $# ]; do
        filename=${@:${OPTIND}:1}

        doit "${processOpts}" "${outputFormat}" "${outputDir}" $filename

        OPTIND=${OPTIND}+1
    done
fi

