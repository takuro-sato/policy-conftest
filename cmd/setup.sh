#!/bin/bash

set -ex

DIR_OF_THIS_FILE=$(cd $(dirname $0); pwd)
cd $DIR_OF_THIS_FILE

# ---- Prepare workspace

WORKSPACE=setup_workspace

if [ -d "$WORKSPACE" ]; then
  echo -e "\e[31mWorkspace directry $DIR_OF_THIS_FILE/$WORKSPACE alrady exists, please make sure to delete it before running this script.\e[0m"
  exit 1
fi

mkdir -p $WORKSPACE
cd $WORKSPACE

# ---- Handle sudo
SUDO=""
SUDOE=""
if [ "$EUID" != 0 ]; then
    SUDO="sudo"
    SUDOE="sudo -E"
fi

# ---- Minimal tools
$SUDO apt update
$SUDO apt install -y git vim tmux curl jq make cmake zip python3-venv

# ---- Install Go

GO_VERSION="1.20"
# Install the latest bugfix version of GO_VERSION
# https://github.com/golang/go/issues/36898 
# install_version=$(curl -sL 'https://go.dev/dl/?mode=json&include=all' | jq -r '.[].version' | grep -m 1 go$GO_VERSION) 
install_version="go1.20.5"
tar_filename=$install_version.linux-amd64.tar.gz
curl -sLO "https://go.dev/dl/$tar_filename"
$SUDO tar -C /usr/local -xzf "$tar_filename"
export GOPATH=$HOME/go
echo 'export GOPATH=$HOME/go' >> ~/.bashrc
echo 'export GOPATH=$HOME/go' >> ~/.profile
export PATH=$PATH:/usr/local/go/bin:$GOPATH/bin
echo 'export PATH=$PATH:/usr/local/go/bin:$GOPATH/bin' >> ~/.bashrc
echo 'export PATH=$PATH:/usr/local/go/bin:$GOPATH/bin' >> ~/.profile
# To avoid permission denied on `go run`
# mkdir -p $HOME/go
# $SUDO chmod +rwx -R $HOME/go
# CURRENT_USER=$(whoami)
# $SUDO chown -R $CURRENT_USER $HOME/go


# ---- Install Rust (for genpolicy)
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

# ---- Install genpolicy dependencies
# https://github.com/microsoft/kata-containers/blob/cc-msft-prototypes/src/tools/genpolicy/Dockerfile#L2
$SUDO apt -y install build-essential protobuf-compiler
$SUDO apt -y install parted qemu btrfs-progs

# ---- Install docker
# https://docs.docker.com/engine/install/ubuntu/

curl -fsSL https://get.docker.com -o get-docker.sh
$SUDO sh get-docker.sh

# ---- Install kubeadm, kubectl, kubelet
# https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/

$SUDO apt-get install -y apt-transport-https ca-certificates gpg

$SUDO mkdir -p /etc/apt/keyrings
curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | $SUDO gpg --yes --dearmor -o /etc/apt/keyrings/kubernetes-archive-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | $SUDO tee /etc/apt/sources.list.d/kubernetes.list

$SUDO apt-get update
$SUDO apt-get install -y kubelet kubeadm kubectl
$SUDO apt-mark hold kubelet kubeadm kubectl

# ---- Setup k alias
cat << EOF >> ~/.bashrc
alias k=kubectl
complete -F __start_kubectl k

source <(kubectl completion bash)

kdebug() {
  kubectl debug node/\$1 -it --image=mcr.microsoft.com/aks/fundamental/base-ubuntu:v0.0.11 -- chroot /host /bin/bash
}
EOF

# ---- Configure crictl for containerd
# https://kubernetes.io/docs/tasks/debug/debug-cluster/crictl/
cat << EOF | $SUDO tee /etc/crictl.yaml
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
EOF

# ---- Install the custom containerd
# https://github.com/takuro-sato/containerd/blob/extract_policy/MEMO.md
pushd $DIR_OF_THIS_FILE/../external/containerd
make
PREFIX=/usr $SUDOE make install
# Assuming `disabled_plugins = ["cri"]` is the only difference from the default
# https://github.com/kubernetes/website/issues/33770
$SUDO rm -f /etc/containerd/config.toml

# systemctl restart doesn't work
$SUDO systemctl kill containerd
$SUDO systemctl start containerd
# TODO: improve
sleep 10

# Check if docker works
$SUDO docker run hello-world

popd

# ---- Install sonobuoy
# https://sonobuoy.io/docs/main/

SONOBUOY_VERSION="0.56.16"
SONOBUOY_TAR_FILE_NAME="sonobuoy_${SONOBUOY_VERSION}_linux_amd64.tar.gz"

curl -sLO "https://github.com/vmware-tanzu/sonobuoy/releases/download/v$SONOBUOY_VERSION/$SONOBUOY_TAR_FILE_NAME"
tar -xvf $SONOBUOY_TAR_FILE_NAME
$SUDO mv sonobuoy /usr/local/bin

# ---- Install Azure CLI
curl -sL https://aka.ms/InstallAzureCLIDeb | $SUDO bash
$SUDO az extension add --name aks-preview
$SUDO az aks install-cli

# ---- Show message
set +x
cd $DIR_OF_THIS_FILE
source preflight-check.sh # include show_login_and_env_var_message()
show_login_and_env_var_message