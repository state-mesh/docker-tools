## Build Torch 2.8.0

```shell
docker run -it --network host --rm --gpus all --ipc=host --ulimit memlock=-1 --ulimit stack=67108864 nvcr.io/nvidia/pytorch:25.06-py3
cd /opt/pytorch/pytorch
export TORCH_CUDA_ARCH_LIST="8.0;8.6;9.0;10.0;12.0+PTX"
export CUDA_ARCH_LIST="8.0 8.6 9.0 10.0 12.0"
echo <<EOF > .ci/docker/common/install_magma_conda.sh
#!/usr/bin/env bash
# Script that replaces the magma install from a conda package

set -eou pipefail

function do_install() {
    cuda_version_nodot=${1/./}

    MAGMA_VERSION="2.6.1"
    magma_archive="magma-cuda${cuda_version_nodot}-${MAGMA_VERSION}-1.tar.bz2"

    anaconda_dir="/usr/local"
    (
        set -x
        tmp_dir=$(mktemp -d)
        pushd ${tmp_dir}
        curl -OLs https://ossci-linux.s3.us-east-1.amazonaws.com/${magma_archive}
        tar -xvf "${magma_archive}"
        mv include/* "${anaconda_dir}/include/"
        mv lib/* "${anaconda_dir}/lib"
        popd
    )
}

do_install $1
EOF

.ci/docker/common/install_magma_conda.sh 12.9 3.12.3
pip install pyyaml
pip install -r requirements.txt
python setup.py bdist_wheel
```

The wheel will be in `dist/`.

