FROM nvcr.io/nvidia/pytorch:25.06-py3

ENV PYTORCH_BUILD_VERSION="2.8.0a0+5228986c39"
ENV PYTORCH_VERSION="2.8.0a0+5228986c39"
ENV TORCH_CUDA_ARCH_LIST="8.0;8.6;9.0;10.0;12.0+PTX"
ENV CMAKE_CUDA_ARCHITECTURES="80;90;100;110;120"
ENV NCCL_P2P_DISABLE=1
ENV NCCL_IB_DISABLE=0
ENV CUDA_ARCHS="8.0 8.6 9.0 10.0 12.0"
ENV CUDA_ARCH_LIST="8.0 8.6 9.0 10.0 12.0"
ENV FLASH_ATTN_CUDA_ARCHS="80;90;100;110;120"
ENV CONDA_DIR=/opt/miniforge
ENV PATH=$CONDA_DIR/bin:$PATH
ENV NIXL_PLUGIN_DIR=/usr/local/nixl/lib/x86_64-linux-gnu/plugins

RUN apt-get update && apt-get install -y gettext pybind11-dev cmake \
    && pip uninstall -y torch distributed-ucxx pylibcudf cudf cupy-cuda12x numba thinc pyarrow numpy dask-cuda cuml cugraph-service-server nx-cugraph distributed-ucx pylibcugraph cugraph kvikio dask-cudf librosa spacy \
    && mkdir -p /opt/densemax/{quant,train,serve,eval} \
    && ldconfig /usr/local/cuda-$(echo $CUDA_VERSION | cut -d. -f1,2)/compat/ \
    && curl -LsSf https://astral.sh/uv/install.sh | sh \
    && mv ~/.local/bin/uv /usr/local/bin/ \
    && mv ~/.local/bin/uvx /usr/local/bin/

COPY common/* /opt/nvidia/entrypoint.d

WORKDIR /opt
RUN wget https://github.com/conda-forge/miniforge/releases/download/25.3.1-0/Miniforge3-25.3.1-0-Linux-x86_64.sh \
    && sh ./Miniforge3-25.3.1-0-Linux-x86_64.sh -b -p /opt/miniforge \
    && rm ./Miniforge3-25.3.1-0-Linux-x86_64.sh \
    && conda init

WORKDIR /opt/pytorch/pytorch


# Uncomment the line below for building torch from scratch
# RUN python -m pip install --no-build-isolation -v -e .
ADD https://densemax.s3.eu-central-1.amazonaws.com/base-image/torch-2.8.0a0%2B5228986c39.nv25.6-cp312-cp312-linux_x86_64.whl /opt

# Quantization
RUN cd /opt/densemax/quant && conda create -n quant python=3.12.11 -y
SHELL ["conda", "run", "-n", "quant", "/bin/bash", "-c"]
RUN pip install /opt/torch-2.8.0a0+5228986c39.nv25.6-cp312-cp312-linux_x86_64.whl "llmcompressor==0.8.0"

# Serving
ADD https://densemax.s3.eu-central-1.amazonaws.com/base-image/vllm-0.11.0rc2.dev356%2Bge246ad6f0.d20251010.cu129-cp38-abi3-linux_x86_64.whl /opt
ADD https://densemax.s3.eu-central-1.amazonaws.com/base-image/xformers-0.0.33%2Bf2043594.d20251009-cp39-abi3-linux_x86_64.whl /opt
ADD https://densemax.s3.eu-central-1.amazonaws.com/base-image/libgdrapi_2.5.1-1_amd64.Ubuntu24_04.deb /opt
ADD https://densemax.s3.eu-central-1.amazonaws.com/base-image/nixl-0.3.0-cp312-cp312-linux_x86_64.whl /opt
ADD https://densemax.s3.eu-central-1.amazonaws.com/base-image/lmcache-0.0.0-cp312-cp312-linux_x86_64.whl /opt
RUN cd /opt/densemax/serve && conda create -n serve python=3.12.11 -y
SHELL ["conda", "run", "-n", "serve", "/bin/bash", "-c"]
RUN dpkg -i /opt/libgdrapi_2.5.1-1_amd64.Ubuntu24_04.deb
RUN sed -i '/nvidia-cudnn-frontend/d' /etc/pip/constraint.txt
RUN pip install /opt/torch-2.8.0a0+5228986c39.nv25.6-cp312-cp312-linux_x86_64.whl \
    && pip install /opt/xformers-0.0.33+f2043594.d20251009-cp39-abi3-linux_x86_64.whl  \
    && pip install /opt/vllm-0.11.0rc2.dev356+ge246ad6f0.d20251010.cu129-cp38-abi3-linux_x86_64.whl  \
    && pip install "triton==3.3.1" "flashinfer-python==0.4.0" "flashinfer-cubin==0.4.0" meson \
    && pip install "flashinfer-jit-cache==0.4.0" --extra-index-url https://flashinfer.ai/whl/cu$(echo $CUDA_VERSION | cut -d. -f1,2 | tr -d '.')  \
    && pip uninstall -y pynvml

#LMCache specifics
RUN cd /opt \
    && wget https://github.com/openucx/ucx/releases/download/v1.19.0/ucx-1.19.0.tar.gz \
    && tar xzf ucx-1.19.0.tar.gz \
    && cd ucx-1.19.0 \
    && ./configure --enable-shared --disable-static --disable-doxygen-doc --enable-optimizations --enable-cma --enable-devel-headers --with-verbs --with-dm --enable-mt \
    && make -j \
    && make -j install-strip \
    && ldconfig

RUN git clone https://github.com/ai-dynamo/nixl \
    && cd nixl \
    && git checkout b1c22edd8fe10e2e5221c107ee51200fce6f09a8 \
    && mkdir build \
    && meson setup build/ --prefix=/usr/local/nixl \
    && cd build \
    && ninja \
    && ninja install \
    && echo "/usr/local/nixl/lib/x86_64-linux-gnu" > /etc/ld.so.conf.d/nixl.conf \
    && echo "/usr/local/nixl/lib/x86_64-linux-gnu/plugins" >> /etc/ld.so.conf.d/nixl.conf \
    && ldconfig

RUN pip install /opt/nixl-0.3.0-cp312-cp312-linux_x86_64.whl  \
    && pip install /opt/lmcache-0.0.0-cp312-cp312-linux_x86_64.whl

# Training
ADD https://densemax.s3.eu-central-1.amazonaws.com/base-image/flash_attn-2.8.3-cp312-cp312-linux_x86_64.whl /opt
RUN cd /opt/densemax/train && conda create -n train python=3.12.11 -y
SHELL ["conda", "run", "-n", "train", "/bin/bash", "-c"]
WORKDIR /opt/densemax/train
RUN pip install /opt/torch-2.8.0a0+5228986c39.nv25.6-cp312-cp312-linux_x86_64.whl \
    && pip install aim \
    && pip install /opt/xformers-0.0.33+f2043594.d20251009-cp39-abi3-linux_x86_64.whl \
    && pip install /opt/flash_attn-2.8.3-cp312-cp312-linux_x86_64.whl \
    && pip install "cut-cross-entropy[transformers] @ git+https://github.com/axolotl-ai-cloud/ml-cross-entropy.git@147ea28"

RUN git clone --depth=1 https://github.com/invergent-ai/axolotl.git \
    && cd axolotl \
    && pip install -r requirements.txt \
    && pip install --no-build-isolation -e .[deepspeed,flash-attn,ring-flash-attn,optimizers,ray] \
    && pip install --no-cache-dir "ray[default,serve,tune]==2.49.1"

RUN mkdir -p /opt/densemax/eval \
    && conda create -n eval python=3.12.1 -y
SHELL ["conda", "run", "-n", "eval", "/bin/bash", "-c"]
WORKDIR /opt/densemax/eval
RUN pip install -U deepeval \
    && pip install deepteam

SHELL ["conda", "run", "-n", "base", "/bin/bash", "-c"]
WORKDIR /opt/densemax
RUN pip install --no-cache-dir "ray[default,serve]==2.49.1"

RUN curl -o /usr/bin/lakectl https://densemax.s3.eu-central-1.amazonaws.com/lakectl \
    && chmod +x /usr/bin/lakectl

# Cleanup
RUN rm /opt/*.whl \
    && rm -rf /opt/pytorch \
    && rm -rf /usr/local/lib/python3.12/dist-packages \
    && rm -rf /root/.cache/pip \
    && apt-get clean

# Custom scripts (keep this section at the end for easy image updates)
RUN mkdir /scripts
COPY train/quantization.py /scripts
COPY quant/quantize.py /scripts

COPY job-entry.sh /usr/bin/job-entry
RUN chmod a+x /usr/bin/job-entry

COPY train/quant.sh /usr/bin/quant
RUN chmod a+x /usr/bin/quant

COPY train/train.sh /usr/bin/train
RUN chmod a+x /usr/bin/train

COPY quant/quantize.sh /usr/bin/quantize
RUN chmod a+x /usr/bin/quantize

ENTRYPOINT ["/bin/bash","-c","--"]

