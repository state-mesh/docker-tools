## Build Torch 2.8.0

Notes:
- NCCL_P2P_DISABLE: disables the peer to peer (P2P) transport, which uses CUDA direct access between GPUs, using NVLink or PCI.
- NCCL_IB_DISABLE: prevents the IB/RoCE transport from being used by NCCL. Instead, NCCL will fall back to using IP sockets.
- SM Architectures:
  - 7.5: NVIDIA T4, NVIDIA Tx Series, RTX 20xx Series, Quadro RTX Series
  - 8.0: NVIDIA A100, NVIDIA A30
  - 8.6: NVIDIA A40, NVIDIA A10,GeForce RTX 30xx Series
  - 8.9: NVIDIA L4, NVIDIA L40, NVIDIA L40S, NVIDIA RTX 6000 Ada, GeForce RTX 40xx Series
  - 9.0: NVIDIA GH200, NVIDIA H200, NVIDIA H100
  - 10.0: NVIDIA GB200, NVIDIA B200
  - 10.3: NVIDIA GB300, NVIDIA B300
  - 12.0: NVIDIA RTX PRO 6000 Blackwell Server Edition, NVIDIA RTX PRO 6000 Blackwell Workstation Edition, GeForce RTX 5090


```shell
docker run -it --network host --rm --gpus all --ipc=host --ulimit memlock=-1 --ulimit stack=67108864 nvcr.io/nvidia/pytorch:25.06-py3

pip uninstall -y numpy distributed-ucxx pylibcudf cudf cupy-cuda12x numba thinc pyarrow numpy dask-cuda cuml cugraph-service-server nx-cugraph distributed-ucx pylibcugraph cugraph kvikio dask-cudf librosa spacy
cd /opt/pytorch/pytorch
export TORCH_CUDA_ARCH_LIST="8.0;8.6;8.9;9.0;10.0;12.0+PTX"
export CUDA_ARCH_LIST="8.0 8.6 8.9 9.0 10.0 12.0"
export PYTORCH_BUILD_VERSION="2.8.0a0+5228986c39"
export NCCL_P2P_DISABLE=0
export NCCL_IB_DISABLE=0
cat > .ci/docker/common/install_magma_conda.sh <<EOF
#!/usr/bin/env bash
# Script that replaces the magma install from a conda package

set -eou pipefail

function do_install() {
    cuda_version_nodot=\${1/./}

    MAGMA_VERSION="2.6.1"
    magma_archive="magma-cuda\${cuda_version_nodot}-\${MAGMA_VERSION}-1.tar.bz2"

    anaconda_dir="/usr/local"
    (
        set -x
        tmp_dir=\$(mktemp -d)
        pushd \${tmp_dir}
        curl -OLs https://ossci-linux.s3.us-east-1.amazonaws.com/\${magma_archive}
        tar -xvf "\${magma_archive}"
        mv include/* "\${anaconda_dir}/include/"
        mv lib/* "\${anaconda_dir}/lib"
        popd
    )
}

do_install \$1
EOF

.ci/docker/common/install_magma_conda.sh 12.9 3.12.3
pip install -r requirements.txt
python setup.py bdist_wheel

pip uninstall torch
pip install dist/*.whl


apt install libwebp-dev
cd /opt/pytorch/vision
export PYTORCH_BUILD_VERSION="2.8.0a0+5228986c39.nv25.6"
export PYTORCH_VERSION="2.8.0a0+5228986c39.nv25.6"
BUILD_VERSION="0.22.0a0+95f10a4e" python setup.py bdist_wheel
```

The wheel will be in `dist/`.

