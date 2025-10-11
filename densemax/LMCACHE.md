## Build LMCache

```shell
apt install -y pybind11-dev cmake

curl -LsSf https://astral.sh/uv/install.sh | sh
mv ~/.local/bin/uv /usr/local/bin/
mv ~/.local/bin/uvx /usr/local/bin/

conda activate serve

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

ldconfig /usr/local/cuda-$(echo $CUDA_VERSION | cut -d. -f1,2)/compat/
export NIXL_PLUGIN_DIR=/usr/local/nixl/lib/x86_64-linux-gnu/plugins

cd /opt
apt install build-essential devscripts debhelper fakeroot pkg-config dkms
git clone https://github.com/NVIDIA/gdrcopy.git
cd gdrcopy/packages
CUDA=/usr/local/cuda ./build-deb-packages.sh
dpkg -i libgdrapi_2.5.1-1_amd64.Ubuntu24_04.deb
cd ..
make install

wget https://github.com/openucx/ucx/releases/download/v1.19.0/ucx-1.19.0.tar.gz
tar xzf ucx-1.19.0.tar.gz
cd ucx-1.19.0
./configure                            \
    --enable-shared                    \
    --disable-static                   \
    --disable-doxygen-doc              \
    --enable-optimizations             \
    --enable-cma                       \
    --enable-devel-headers             \
    --with-verbs                       \
    --with-dm                          \
    --enable-mt
make -j
make -j install-strip
ldconfig
cd /opt


git clone https://github.com/ai-dynamo/nixl
cd nixl
git checkout b1c22edd8fe10e2e5221c107ee51200fce6f09a8
sed -i '/torch/d' /opt/nixl/pyproject.toml

pip install meson
mkdir build
meson setup build/ --prefix=/usr/local/nixl
cd build && ninja && ninja install
echo "/usr/local/nixl/lib/x86_64-linux-gnu" > /etc/ld.so.conf.d/nixl.conf
echo "/usr/local/nixl/lib/x86_64-linux-gnu/plugins" >> /etc/ld.so.conf.d/nixl.conf
ldconfig

cd /opt/nixl
uv build --wheel --out-dir ./dist

git clone https://github.com/LMCache/LMCache.git
cd LMCache
pip install -r requirements/build.txt

MAX_JOBS=16 NVCC_THREADS=8 python3 setup.py bdist_wheel --dist-dir=dist_lmcache
```