#!/bin/bash

set -e

DIR_OF_THIS_FILE=$(cd $(dirname $0); pwd)
cd $DIR_OF_THIS_FILE
PROJECT_ROOT_DIR=$(cd ..; pwd)
cd $PROJECT_ROOT_DIR

# ---- Handle sudo
SUDO=""
SUDOE=""
if [ "$EUID" != 0 ]; then
    SUDO="sudo"
    SUDOE="sudo -E"
fi

# ---- Preflight check
echo "@test.sh: ---- Preflight check"
./cmd/run-preflight-check.sh


set -x

# ---- Set env vars that are reused
echo "@test.sh: ---- Set env vars that are reused"
export IMAGE_SERVER=$(az acr show --name $ACR_REGISTRY_NAME --query loginServer --output tsv  | sed 's/\r//g')


# Skip some tests
# Removing gc test due to lack of memory, `[Disruptive]` tests may kill/evicts webhook
export CONFTEST_SKIP='(.*Garbage collector.*|.*evicts pods with minTolerationSeconds.*|.*removing taint cancels eviction.*).*\[Conformance\]'

# ---- Build extract-kubeapi-webhook
echo "@test.sh: ---- Build extract-kubeapi-webhook"
pushd extract-kubeapi-webhook
sudo -E az acr login --name $ACR_REGISTRY_NAME
sudo -E env "PATH=$PATH" make push-image
# The above breaks $HOME/go
mkdir -p $HOME/go
$SUDO chmod +rwx -R $HOME/go
CURRENT_USER=$(whoami)
$SUDO chown -R $CURRENT_USER $HOME/go
popd

# ---- Build conformance test image
echo "@test.sh: ---- Build conformance test image"
pushd external/kubernetes
make WHAT="test/e2e/e2e.test github.com/onsi/ginkgo/v2/ginkgo cmd/kubectl test/conformance/image/go-runner"
pushd test/conformance/image
export REGISTRY=$IMAGE_SERVER
TARGET_VERSION=dev
sudo -E az acr login --name $ACR_REGISTRY_NAME
sudo -E env "PATH=$PATH" make push VERSION=$TARGET_VERSION ARCH=amd64
popd
# The above breaks $HOME/go
mkdir -p $HOME/go
$SUDO chmod +rwx -R $HOME/go
CURRENT_USER=$(whoami)
$SUDO chown -R $CURRENT_USER $HOME/go
popd

# ---- Run dummy conformance test to get image hashes used in the test (async)
echo "@test.sh: ---- Run dummy conformance test to get image hashes used in the test (async)"
pushd env-containerd
DUMMY_RUN=true ./reset-setup-test.sh
popd

# ---- Run 1st conformance test
echo "@test.sh: ---- Run 1st conformance test"
pushd env-containerd-aks
./test.sh
cp $LOG_DIR/first-run/test-to-ns.txt ../gen-policy/test-to-ns.txt
popd

# ---- Wait for dummy conformance test to finish
echo "@test.sh: ---- Wait for dummy conformance test to finish"
# It runs conformance test locally.
# This in necessary just to pull docker images used in the test
# so that gen-polish.sh can look up image name from image hash.
# TODO: It would be efficient if it gets the look up table from the AKS cluster.
pushd env-containerd
./get-result.sh
popd

# ---- Generate policy based on the 1st conformance test run
echo "@test.sh: ---- Generate policy based on the 1st conformance test run"
pushd gen-policy
./gen-policy.sh
BACKUP_DIR="$LOG_DIR/gen-policy-workspace" ./backup-workspace.sh
popd

# ---- Build apply-policy-webhook
echo "@test.sh: ---- Build apply-policy-webhook"
pushd apply-policy-webhook
./update_policy_dir.sh # To use generaeted policy
sudo -E az acr login --name $ACR_REGISTRY_NAME
sudo -E env "PATH=$PATH" make push-image
# The above breaks $HOME/go
mkdir -p $HOME/go
$SUDO chmod +rwx -R $HOME/go
CURRENT_USER=$(whoami)
$SUDO chown -R $CURRENT_USER $HOME/go
popd

# ---- Create kata-cc environment for 2nd/actual conformance test
echo "@test.sh: ---- Create kata-cc environment for 2nd/actual conformance test"
pushd env-katacc
if [ "$REUSE_AKS" == "true" ]; then
    az aks get-credentials --resource-group "${RESOURCE_GROUP}" --name marinerkata --overwrite-existing
    ./rerun-test.sh
else
    ./setup-katacc-aks.sh
    ../apply-policy-webhook/deploy.sh
    sleep 60 # TODO: improve
    ./test.sh
fi
popd

# ---- Brief validation of results
echo "@test.sh: ---- Brief validation of results"
if ! diff $LOG_DIR/first-run/test-to-ns.txt $LOG_DIR/second-run/test-to-ns.txt; then
    echo "Mapping from test to namespace is inconsistent."
    exit 1
fi

# ---- Create summary
echo "@test.sh: ---- Create summary"
first_run_failed_tests=$(cat $LOG_DIR/first-run/failed-tests.txt)
gen_policy_failed_tests=$(cat $LOG_DIR/gen-policy-workspace/gen-policy-failed-test-list.txt)
gen_policy_num_failed_tests=$(echo $gen_policy_num_failed_tests | wc -l)
second_run_num_passed=$(cat $LOG_DIR/second-run/passed-tests.txt | wc -l)
second_run_num_failed=$(cat $LOG_DIR/second-run/failed-tests.txt | wc -l)
num_total=$(cat $LOG_DIR/second-run/all-tests.txt | wc -l)
num_skipped=$((num_total - second_run_num_passed - second_run_num_failed))
second_run_failed_tests=$(cat $LOG_DIR/second-run/failed-tests.txt)
# We don't include first run's failing tests, because we know they doesn't affect following steps.
total_failed_tests=$(cat << EOF
$(echo "$gen_policy_failed_tests")
$(echo "$second_run_failed_tests")
EOF
)
total_failed_tests_unique=$(echo "$total_failed_tests" | sort -u)
num_total_failed=$(echo "$total_failed_tests_unique" | wc -l)
num_overwrapped_failed=$((gen_policy_num_failed_tests + second_run_num_failed - num_total_failed))
num_total_passed=$((second_run_num_passed - gen_policy_num_failed_tests + num_overwrapped_failed))

jq --null-input \
    --argjson num_passed "$num_total_passed" \
    --argjson num_failed "$num_total_failed" \
    --argjson num_skipped "$num_skipped" \
    --argjson num_total "$num_total" \
    --argjson first_run "$(cat $LOG_DIR/first-run/result.json)" \
    --argjson gen_policy "$(cat $LOG_DIR/gen-policy-workspace/result.json)" \
    --argjson second_run "$(cat $LOG_DIR/second-run/result.json)" \
    '{"num_passed": $num_passed, "num_failed": $num_failed, "num_skipped": $num_skipped, "num_total": $num_total, "first_run": $first_run, "gen_policy": $gen_policy, "second_run": $second_run}' \
    > $LOG_DIR/result.json

cat << EOF > $LOG_DIR/summary.txt
## Summary
Passed: ${num_total_passed}, Failed: ${num_total_failed}, Skipped: ${num_skipped}, Total: ${num_total}

'Passed' here is number of test cases that passed both in 'policy generation' and '2nd run'.
'Failed' here is number of test cases either 'policy generation' or '2nd run' failed.

## 1st run
$(cat $LOG_DIR/first-run/summary.txt)

## generate policy
$(cat $LOG_DIR/gen-policy-workspace/summary.txt)

## 2nd run (actual test)
$(cat $LOG_DIR/second-run/summary.txt)
EOF

echo "Printing summary..."
cat $LOG_DIR/summary.txt
echo ""
echo ""

# ---- Update graph
echo "@test.sh: ---- Update graph"
# https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Date#date_time_string_format
resultsCSV=${PROJECT_ROOT_DIR}/results.csv
resultsPNG=${PROJECT_ROOT_DIR}/results.png

# resultsCSV doesn't exist
if ! [ -f "$resultsCSV" ]; then
    # Create the file and header
    echo "run,passed,failed,policy generation error,skipped,total" > $resultsCSV
fi

if [ -z "$RUN_DATETIME" ]; then
    # If RUN_DATETIME is not set, assume that log directory name has format of "conftest-2023-0808-120910" for example.
    LOG_DIR_NAME=$(basename $LOG_DIR)
    export RUN_DATETIME="${LOG_DIR_NAME#*-}" # Remove everything before the first "-"
fi

echo "$RUN_DATETIME,${num_total_passed},${num_total_failed},${gen_policy_num_failed_tests},${num_skipped},${num_total}" >> $resultsCSV

ENV_NAME=env
PYTHON_DIR=${DIR_OF_THIS_FILE}/python/$ENV_NAME
if [ ! -f "${PYTHON_DIR}/bin/activate" ]; then
    python3 -m venv $PYTHON_DIR
fi

source $PYTHON_DIR/bin/activate

pip install -U -q pip
pip install -q -U -r ${DIR_OF_THIS_FILE}/python/requirements.txt

python ${DIR_OF_THIS_FILE}/plot_results.py $resultsCSV $resultsPNG

# ---- Upload log
echo "@test.sh: ---- Upload log"

zip -r $LOG_DIR.zip $LOG_DIR


shareName="conftestshare"
directoryName=results

if [ "$(az storage share exists --account-name $AZ_STORAGE_ACCOUNT -n $shareName | jq .exists -r)" != "true" ]; then
    echo "Share $shareName doesn't exist. Creating..."
    az storage share-rm create \
        --storage-account $AZ_STORAGE_ACCOUNT \
        --name $shareName \
        --quota 1024 \
        --enabled-protocols SMB \
        --output none
else
    echo "Share $shareName found."
fi

if [ "$(az storage directory exists --account-name $AZ_STORAGE_ACCOUNT --share-name $shareName --name $directoryName | jq .exists -r)" != "true" ]; then
    echo "Directory $directoryName doesn't exist. Creating..."
    az storage directory create \
        --account-name $AZ_STORAGE_ACCOUNT \
        --share-name $shareName \
        --name $directoryName\
        --output none
else
    echo "Directory $directoryName found."
fi

logFilePaht="results/$(basename "$LOG_DIR.zip")"
az storage file upload \
    --account-name $AZ_STORAGE_ACCOUNT \
    --share-name $shareName \
    --source "$LOG_DIR.zip" \
    --path "$logFilePaht"

# ---- Show message
set +x
echo "Test finished. The logs are in $LOG_DIR and also in Azure storage (account: $AZ_STORAGE_ACCOUNT, share: $shareName, path: $logFilePaht)"

if [ "$DELETE_AKS_AFTER_RUN" == "true" ]; then
    az group delete -n $RESOURCE_GROUP -y
else
    echo -e "\e[34mYou may want to run \`az group delete -n $RESOURCE_GROUP\` to delete the AKS cluster.\e[0m"
fi
