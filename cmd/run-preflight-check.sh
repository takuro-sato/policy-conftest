#!/bin/bash

set -e

DIR_OF_THIS_FILE=$(cd $(dirname $0); pwd)
cd $DIR_OF_THIS_FILE
PROJECT_ROOT_DIR=$(cd ..; pwd)
cd $PROJECT_ROOT_DIR

source ./cmd/preflight-check.sh # include check_install() and check_login_and_env_vars()
check_install
check_login_and_env_vars
