## build is working but pytorch is not

git clone --recursive -b v1.3.0 https://github.com/pytorch/FBGEMM.git
cd FBGEMM/fbgemm_gpu/
pip install -r requirements_genai.txt
export package_name=fbgemm-gpu-genai
export ARCH=$(uname -m)
export NVML_LIB_PATH=/usr/lib/x86_64-linux-gnu/libnvidia-ml.so.1
export export NCCL_LIB_PATH=/usr/lib/x86_64-linux-gnu/libnccl.so.2
export python_tag=py312

unset TORCH_CUDA_ARCH_LIST

python setup.py bdist_wheel \
    --package_channel=release \
    --python-tag="py312" \
    --plat-name="linux_${ARCH}" \
    --nvml_lib_path=${NVML_LIB_PATH} \
    --nccl_lib_path=${NCCL_LIB_PATH} \
    -DTORCH_CUDA_ARCH_LIST="8.0;9.0a;10.0a;12.0a"
