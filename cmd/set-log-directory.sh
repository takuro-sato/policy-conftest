#!/bin/bash

set -e

DIR_OF_THIS_FILE=$(cd $(dirname $0); pwd)
cd $DIR_OF_THIS_FILE
PROJECT_ROOT_DIR=$(cd ..; pwd)
cd $PROJECT_ROOT_DIR

if [ -z "$LOG_PARENT_DIR" ]; then
    export LOG_PARENT_DIR="${PROJECT_ROOT_DIR}/logs"
fi

export RUN_DATETIME=$(date +"%Y-%m%d-%H%M%S")

if [ -z "$LOG_DIR" ]; then
    # Doesn't provide perfect unique name, but should be enough for the purpose.
    export LOG_DIR="${LOG_PARENT_DIR}/conftest-${RUN_DATETIME}"
fi

echo "$LOG_DIR"