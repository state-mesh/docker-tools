## Build vLLM 11.x

Notes:
- Compilation requires 250GB RAM !
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
docker run -it --network host --rm --gpus all --ipc=host --ulimit memlock=-1 --ulimit stack=67108864 statemesh/densemax:1.0.0

conda activate serve

# copy the pre-built torch wheel to /opt

sed -i '/nvidia-cudnn-frontend/d' /etc/pip/constraints.txt

pip uninstall -y torch flash_attn
pip install cmake pynvml nvidia-ml-py /opt/torch-2.8.0a0+5228986c39.nv25.6-cp312-cp312-linux_x86_64.whl
pip install "flashinfer-python==0.4.0"

cd /opt

export FLASH_ATTN_CUDA_ARCHS="80;90;100;110;120"
export CMAKE_CUDA_ARCHITECTURES="80;90;100;110;120"
export TORCH_CUDA_ARCH_LIST="8.0;8.6;9.0;10.0;12.0+PTX"
export USE_CUDA=1
export CUDA_HOME=/usr/local/cuda
export NCCL_P2P_DISABLE=0
export NCCL_IB_DISABLE=0
export MAX_JOBS=16
export NVCC_THREADS=16
export CUDA_ARCHS="8.0 8.6 9.0 10.0 12.0"
export CUDA_ARCH_LIST="8.0 8.6 9.0 10.0 12.0"

# if you built the wheel before, just copy it and install it
git clone -b v2.8.3 https://github.com/Dao-AILab/flash-attention.git
cd flash-attention
MAX_JOBS=16 NVCC_THREADS=8 FLASH_ATTENTION_FORCE_CXX11_ABI="TRUE" FLASH_ATTENTION_FORCE_BUILD="TRUE" python setup.py bdist_wheel
python setup.py bdist_wheel
pip install dist/flash_attn-2.8.3-cp312-cp312-linux_x86_64.whl
# copy the wheel from container
cd /opt

# if you built the wheel before, just copy it and install it
git clone https://github.com/facebookresearch/xformers.git
cd xformers
git submodule update --init --recursive
cd third_party/flash-attention; git checkout v2.8.3; cd ../..
MAX_JOBS=16 NVCC_THREADS=8 FLASH_ATTENTION_FORCE_CXX11_ABI="TRUE" FLASH_ATTENTION_FORCE_BUILD="TRUE" python setup.py bdist_wheel
pip install dist/xformers-0.0.33....
# copy the wheel from container

cd /opt

git clone https://github.com/linux-rdma/rdma-core.git
cd rdma-core
git checkout v59.0
mkdir build && cd build
CFLAGS=-fPIC cmake -DENABLE_STATIC=1 -DNO_PYVERBS=1 -DNO_MAN_PAGES=1 -GNinja ..
ninja
ninja install
cd /opt

git clone https://github.com/vllm-project/vllm.git
python use_existing_torch.py
pip install -r requirements/build.txt --no-build-isolation
TORCH_CUDA_ARCH_LIST="9.0a 10.0a" ./tools/install_deepgemm.sh --cuda-version 12.9.1
TORCH_CUDA_ARCH_LIST="10.0;10.0a+PTX;12.0+PTX" bash ./tools/ep_kernels/install_python_libraries.sh
BUILD_EXTRAS="tensorizer,flashinfer,fastsafetensors" python3 setup.py bdist_wheel --dist-dir=dist --py-limited-api=cp38
```