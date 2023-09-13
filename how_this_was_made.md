# How this repo was made

```
mkdir -p gen-policy/lib
git submodule add -b additional_exec_command https://github.com/takuro-sato/kata-containers.git gen-policy/lib/kata-containers

mkdir -p external
git submodule add -b conftest_deterministic https://github.com/takuro-sato/kubernetes external/kubernetes
git submodule add -b extract_policy https://github.com/takuro-sato/containerd external/containerd
```