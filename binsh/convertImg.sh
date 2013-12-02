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
Uasge: $0 -s SIZE [-o OUTPUT_DIR] FILE...
Resize the given image files.
EOF
}

while getopts "s:o:r:" ARGNAME; do
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
        ?)
            usage
            exit 1
    esac
done

if [[ -z "${processOpts}" ]]
then
    usage
    exit 1
fi

if [ $# -lt ${OPTIND} ]
then
    # No filename pattern given
    usage
    exit 1
fi

if [[ -z ${outputDir} ]]
then
    outputDir='out'
fi

mkdir -p ${outputDir}

while [ ${OPTIND} -le $# ]; do
    filename=${@:${OPTIND}:1}
    
    echo "Processing \"${filename}\""
    convert "${filename}" ${processOpts} "${outputDir}/${filename}"

    OPTIND=${OPTIND}+1
done

