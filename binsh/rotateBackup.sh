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

usage()
{
cat << EOF
Usage:
    $0 
    $0 -h
EOF
}

# Default number of last backup to keep by hour, week, day & month. -1 to keep all
NB_HOURLY_KEPT=36
NB_DAYLY_KEPT=10
NB_WEEKLY_KEPT=6
NB_MONTHLY_KEPT=-1

BACKUP_ROOT=""
BACKUP_SRC=""
NO_CHANGE=0

# Parse arguments
while getopts "hr:s:o:d:w:m:n" ARGNAME; do
    case ${ARGNAME} in
        r)
            BACKUP_ROOT=${OPTARG}
            ;;
        s)
            BACKUP_SRC=${OPTARG}
            ;;
        o)
            NB_HOURLY_KEPT=${OPTARG}
            ;;
        d)
            NB_DAYLY_KEPT=${OPTARG}
            ;;
        w)
            NB_WEEKLY_KEPT=${OPTARG}
            ;;
        m)
            NB_MONTHLY_KEPT=${OPTARG}
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

if [ "x${BACKUP_ROOT}" = "x" ]; then
    echo "Error: No backup root given"
    usage
    exit 1
fi

if [ "x${BACKUP_SRC}" = "x" ]; then
    echo "Error: No backup source given"
    usage
    exit 1
fi

# Deletes the first entries in the given path until the number of entries in the path
# becomes lower or equal than the given limit
#
# Param:
# $1: Path to inspect
# $2: Number of entries to keep
deleteFirst()
{
    DIR_TO_CLEAN=$1
    NB_KEPT_ENTRIES=$2

    if [ ${NB_KEPT_ENTRIES} -eq -1 ]; then
        # Keep all
        return 0
    fi

    if [ ! -d ${DIR_TO_CLEAN} ];
    then
        echo "Error: ${DIR_TO_CLEAN} is not a directory"
        return 1
    fi

    DIR_ENTRIES=(`ls ${DIR_TO_CLEAN}`)
    NB_DIR_ENTRIES=${#DIR_ENTRIES[@]}

    while [ ${NB_DIR_ENTRIES} -gt ${NB_KEPT_ENTRIES} ]; do
        ENTRY_TO_DELETE=${DIR_ENTRIES[0]}

        echo "Removing ${DIR_TO_CLEAN}/${ENTRY_TO_DELETE}"
        if [ ${NO_CHANGE} = 0 ]; then
            rm -rf ${DIR_TO_CLEAN}/${ENTRY_TO_DELETE}
        fi

        unset DIR_ENTRIES[0]
        let NB_DIR_ENTRIES-=1
    done

    return 0
}

# Backup and rotate
#
# Params:
# $1: Source directory to backup
# $2: Destination directory of the backup (without date directory)
# $3: Number of backups to keep in destination directory
# $4: Backup threshold
backupAndRotate()
{
    SRC_DIR=$1
    DEST_DIR=$2
    NB_KEPT_ENTRIES=$3
    THRESHOLD=$4

    DIR_ENTRIES=(`ls ${DEST_DIR}`)
    NB_DIR_ENTRIES=${#DIR_ENTRIES[@]}
    
    if [ ${NB_DIR_ENTRIES} -gt 0 ]; then
        LAST_BACKUP=${DIR_ENTRIES[${NB_DIR_ENTRIES} - 1]}

        if [[ ! ${LAST_BACKUP} =~ ^[0-9]{14}$ || ! -d ${DEST_DIR}/${LAST_BACKUP} ]]; then
            echo "Last backup is invalid: ${DEST_DIR}/${LAST_BACKUP}"
            return 1
        fi

        echo "Last backup: ${DEST_DIR}/${LAST_BACKUP}"
    else
        LAST_BACKUP=0
    fi
    if [ ${LAST_BACKUP} -lt ${THRESHOLD} ]; then
        echo "Backing up ${SRC_DIR} to ${DEST_DIR}/${CURRENT_DATE}"
        if [ ${NO_CHANGE} = 0 ]; then
            cp -al ${SRC_DIR} ${DEST_DIR}/${CURRENT_DATE}
        fi
        deleteFirst ${DEST_DIR} ${NB_KEPT_ENTRIES}
        return $?
    else
        echo "No backup needed"
    fi

    return 2
}

# Create backup directory structure if needed
mkdir -p ${BACKUP_ROOT}/hourly
if [ $? -ne 0 ]; then
    exit 1
fi
mkdir -p ${BACKUP_ROOT}/dayly
if [ $? -ne 0 ]; then
    exit 1
fi
mkdir -p ${BACKUP_ROOT}/weekly
if [ $? -ne 0 ]; then
    exit 1
fi
mkdir -p ${BACKUP_ROOT}/monthly
if [ $? -ne 0 ]; then
    exit 1
fi

DATE_FORMAT="+%Y%m%d%H%M%S"
CURRENT_DATE_TIME_C=`LC_TIME=C date`
CURRENT_DATE=`date --date="${CURRENT_DATE_TIME_C}" ${DATE_FORMAT}`

# Hourly backup
HOURLY_THRESHOLD=`date --date="${CURRENT_DATE_TIME_C} -1 hour" ${DATE_FORMAT}`
backupAndRotate ${BACKUP_SRC} "${BACKUP_ROOT}/hourly" ${NB_HOURLY_KEPT} ${HOURLY_THRESHOLD}
if [ $? -ne 0 ]; then
    exit $?
fi

# Dayly backup
DAYLY_THRESHOLD=`date --date="${CURRENT_DATE_TIME_C} -1 day" ${DATE_FORMAT}`
backupAndRotate ${BACKUP_SRC} "${BACKUP_ROOT}/dayly" ${NB_DAYLY_KEPT} ${DAYLY_THRESHOLD}
if [ $? -ne 0 ]; then
    exit $?
fi

# Weekly threshold
WEEKLY_THRESHOLD=`date --date="${CURRENT_DATE_TIME_C} -1 week" ${DATE_FORMAT}`
backupAndRotate ${BACKUP_SRC} "${BACKUP_ROOT}/weekly" ${NB_WEEKLY_KEPT} ${WEEKLY_THRESHOLD}
if [ $? -ne 0 ]; then
    exit $?
fi

# Monthly threshold
MONTHLY_THRESHOLD=`date --date="${CURRENT_DATE_TIME_C} -1 month" ${DATE_FORMAT}`
backupAndRotate ${BACKUP_SRC} "${BACKUP_ROOT}/monthly" ${NB_MONTHLY_KEPT} ${MONTHLY_THRESHOLD}
if [ $? -ne 0 ]; then
    exit $?
fi


