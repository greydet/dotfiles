#! /bin/bash
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

#set -x

usage()
{
cat << EOF
Usage:
    $0 [-a <SERVER_ADDRESS>] [-p <PORT>] [-u <DISTANT_USER>] [-f <BACKUP_LIST_FILE>] [-i] [-n]
    $0 -h
EOF
}

SYNC_LIST=${HOME}/.backupSync
ROTATION_SCRIPT_NAME="rotateBackup.sh"

SCRIPT_PATH=`dirname ${0}`
DATE_CMD="eval date '+%d/%m/%Y %T'"

SERVER_ADDRESS=""
SERVER_USER=""
SERVER_PORT=""
LOCAL_TO_DIST=1
NO_CHANGE=0

buildServerAccess()
{
    if [ "x${SERVER_ADDRESS}" != "x" ]; then
        if [ "x$1" != "x" ]; then
            SERVER_PATH="${SERVER_ADDRESS}:$1"
        else
            SERVER_PATH="${SERVER_ADDRESS}"
        fi
        if [ "x${SERVER_USER}" != "x" ]; then
            SERVER_PATH="${SERVER_USER}@${SERVER_PATH}"
        fi
    elif [ "x$1" != "x" ]; then
        SERVER_PATH=$1
    else
        SERVER_PATH=""
    fi

    echo ${SERVER_PATH}
}

# Parse arguments
while getopts "hina:p:u:f:" ARGNAME; do
    case ${ARGNAME} in
        a)
            SERVER_ADDRESS=${OPTARG}
            ;;
        p)
            SERVER_PORT=${OPTARG}
            ;;
        u)
            SERVER_USER=${OPTARG}
            ;;
        f)
            SYNC_LIST=${OPTARG}
            ;;
        i)
            LOCAL_TO_DIST=0
            ;;
        n)
            NO_CHANGE=1
            ;;
        h)
            usage
            exit 0
            ;;
        ?)
            usage
            exit 1
    esac
done

if [ ! -r ${SYNC_LIST} ]; then
    echo "Error: File ${SYNC_LIST} is not readable."
    exit 1
fi

# Prevent executing concurrent backups
SYNC_LOCK=${SYNC_LIST}.lock
if [ -e ${SYNC_LOCK} ]; then
    echo "Error: Lock file already exists: ${SYNC_LOCK}."
    exit 1
fi

touch ${SYNC_LOCK}

# Rebuild ssh-agent variables (needed for cron)
export SSH_AGENT_PID=`ps ax | grep ssh-agent | grep -v grep | awk '{printf $1}'`
if [ "x${SSH_AGENT_PID}" = "" ]; then
    # ssh-agent not found, start a new one
    OUT=`ssh-agent -s | grep -v echo`
    $OUT
else
    export SSH_AUTH_SOCK=`find /tmp/ -path '*keyring*' -name '*ssh*' -print 2> /dev/null`
fi

RET_CODE=0
FROM_LIST=()
TO_LIST=()
BACKUP_ROOT=""
ROTATION_ROOT=""

# Read ${SYNC_LIST} line by line
while read -r SYNC_ENTRY; do
    SYNC_ENTRY=`echo ${SYNC_ENTRY} | sed 's/^ *\(.*\) *$/\1/g'` # Remove leading & trailing characters
    if [ "x${SYNC_ENTRY}" = "x" ]; then
        # Empty line
        continue
    fi
    if [ "${SYNC_ENTRY:0:1}" = "#" ]; then
        # Comment line
        continue
    fi

    if [[ "${SYNC_ENTRY}" == *=* ]]; then
        # Property
        VAR_NAME=`echo ${SYNC_ENTRY} | sed 's/\(.*\)=.*/\1/g'`
        VAR_VALUE=`echo ${SYNC_ENTRY} | sed 's/.*=\(.*\)/\1/g'`

        case $VAR_NAME in
            *BACKUP_ROOT*)
                BACKUP_ROOT=${VAR_VALUE}
            ;;
            *ROTATION_ROOT*)
                ROTATION_ROOT=${VAR_VALUE}
            ;;
            *)
                echo "Error: Invalid property: ${SYNC_ENTRY}"
                RET_CODE=1
                break
            ;;
        esac
    elif [[ "${SYNC_ENTRY}" == *:* ]]; then
        # Backup mapping entry
        FROM_PATH=`echo ${SYNC_ENTRY} | sed 's/\(.*\):.*/\1/g'`
        TO_PATH=`echo ${SYNC_ENTRY} | sed 's/.*:\(.*\)/\1/g'`

        FROM_LIST+=(${FROM_PATH})
        TO_LIST+=(${TO_PATH})
    else
        echo "Error: Invalid configuration entry: ${SYNC_ENTRY}"
        RET_CODE=1
        break
    fi
done < ${SYNC_LIST}

# Prepare rsync & scp options
RSYNC_OPT="-avz --delete"
SCP_OPT="-p"
SSH_OPT=""
ROTATION_OPT=""
if [ ${NO_CHANGE} -eq 1 ]; then
    RSYNC_OPT="$RSYNC_OPT -n"
    ROTATION_OPT="$ROTATION_OPT -n"
fi
if [ "x${SERVER_ADDRESS}" != "x" ]; then
    if [ "x${SERVER_PORT}" = "x" ]; then
        RSYNC_OPT="$RSYNC_OPT -e 'ssh'"
    else
        RSYNC_OPT="$RSYNC_OPT -e 'ssh -p ${SERVER_PORT}'"
        SCP_OPT="${SCP_OPT} -P ${SERVER_PORT}"
        SSH_OPT="${SSH_OPT} -p ${SERVER_PORT}"
    fi
fi

echo `$DATE_CMD`": Backup started"

# Iterate over backup entries
i=0
while [ $i -lt ${#FROM_LIST[@]} ]; do
    FROM_PATH=${FROM_LIST[$i]}
    TO_PATH=${TO_LIST[$i]}

    if [ "x${SERVER_ADDRESS}" != "x" ]; then
        if [ ${LOCAL_TO_DIST} -eq 1 ]; then
            TO_PATH=`buildServerAccess ${TO_PATH}`
        else
            FROM_PATH=`buildServerAccess ${FROM_PATH}`
        fi
    fi
    echo "Backing up from '${FROM_PATH}' to '${TO_PATH}'"

    eval rsync ${RSYNC_OPT} ${FROM_PATH} ${TO_PATH}
    RET_CODE=$?
    if [ ${RET_CODE} -ne 0 ]; then
        break
    fi

    let i+=1
done

# Backup rotation only in local to distant direction and if variable were set in sync file
if [ "x${BACKUP_ROOT}" != "x" -a "x${ROTATION_ROOT}" != "x" -a ${LOCAL_TO_DIST} -eq 1 ]; then
    ROTATION_SCRIPT="${SCRIPT_PATH}/${ROTATION_SCRIPT_NAME}"
    if [ -r ${ROTATION_SCRIPT} ]; then
        echo ""
        echo `$DATE_CMD`": Performing backup rotation..."
        scp ${SCP_OPT} ${ROTATION_SCRIPT} `buildServerAccess "/tmp/${ROTATION_SCRIPT_NAME}"`
        ssh ${SSH_OPT} `buildServerAccess` "/tmp/${ROTATION_SCRIPT_NAME} ${ROTATION_OPT} -s ${BACKUP_ROOT} -r ${ROTATION_ROOT}"
    else
        echo "Error: Rotation script is not available ${ROTATION_SCRIPT}"
    fi
fi

echo `$DATE_CMD`": Backup finished"

rm ${SYNC_LOCK}
exit ${RET_CODE}
