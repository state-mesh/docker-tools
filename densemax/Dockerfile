FROM nvcr.io/nvidia/pytorch:25.06-py3

RUN apt-get update && apt-get install -y gettext && \
    pip uninstall -y torch distributed-ucxx pylibcudf cudf cupy-cuda12x numba thinc pyarrow numpy dask-cuda cuml cugraph-service-server nx-cugraph distributed-ucx pylibcugraph cugraph kvikio dask-cudf librosa spacy && \
    mkdir -p /opt/densemax/{quant,train,serve}

COPY common/* /opt/nvidia/entrypoint.d

WORKDIR /opt/pytorch/pytorch
ENV PYTORCH_BUILD_VERSION="2.8.0a0+5228986c39"
ENV PYTORCH_VERSION="2.8.0a0+5228986c39"
ENV TORCH_CUDA_ARCH_LIST="12.0+PTX"
ENV FLASH_ATTN_CUDA_ARCHS="120"
ENV CUDA_ARCH_LIST="12.0"
ENV CONDA_DIR=/opt/miniforge
ENV PATH=$CONDA_DIR/bin:$PATH

# Uncomment the line below for building torch from scratch
# RUN python -m pip install --no-build-isolation -v -e .
ADD https://densemax.s3.eu-central-1.amazonaws.com/base-image/torch-2.8.0a0%2B5228986c39.nv25.6-cp312-cp312-linux_x86_64.whl /opt

WORKDIR /opt
ADD https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-x86_64.sh /opt
RUN sh ./Miniforge3-Linux-x86_64.sh -b -p /opt/miniforge && \
    rm ./Miniforge3-Linux-x86_64.sh && \
    conda init

# Quantization
RUN cd /opt/densemax/quant && conda create -n quant python=3.12.3 -y
SHELL ["conda", "run", "-n", "quant", "/bin/bash", "-c"]
RUN pip install /opt/torch-2.8.0a0+5228986c39.nv25.6-cp312-cp312-linux_x86_64.whl "llmcompressor==0.8.0"

# Serving
ADD https://densemax.s3.eu-central-1.amazonaws.com/base-image/vllm-0.11.0rc2.dev70%2Bge47433b3c.d20250930.cu129-cp38-abi3-linux_x86_64.whl /opt
ADD https://densemax.s3.eu-central-1.amazonaws.com/base-image/xformers-0.0.33%2B5146f2ab.d20250930-cp39-abi3-linux_x86_64.whl /opt
ADD https://densemax.s3.eu-central-1.amazonaws.com/base-image/flashinfer_python-0.3.1-cp39-abi3-linux_x86_64.whl /opt
RUN cd /opt/densemax/serve && conda create -n serve python=3.12.3 -y
SHELL ["conda", "run", "-n", "serve", "/bin/bash", "-c"]
RUN pip install /opt/torch-2.8.0a0+5228986c39.nv25.6-cp312-cp312-linux_x86_64.whl && \
    pip install /opt/xformers-0.0.33+5146f2ab.d20250930-cp39-abi3-linux_x86_64.whl && \
    pip install /opt/flashinfer_python-0.3.1-cp39-abi3-linux_x86_64.whl && \
    pip install /opt/vllm-0.11.0rc2.dev70+ge47433b3c.d20250930.cu129-cp38-abi3-linux_x86_64.whl && \
    pip install "triton==3.3.1" && \
    pip uninstall -y pynvml

# Training
RUN cd /opt/densemax/train && conda create -n train python=3.12.3 -y
SHELL ["conda", "run", "-n", "train", "/bin/bash", "-c"]
WORKDIR /opt/densemax/train
RUN pip install /opt/torch-2.8.0a0+5228986c39.nv25.6-cp312-cp312-linux_x86_64.whl && \
    pip install /opt/xformers-0.0.33+5146f2ab.d20250930-cp39-abi3-linux_x86_64.whl && \
    pip install "cut-cross-entropy[transformers] @ git+https://github.com/axolotl-ai-cloud/ml-cross-entropy.git@147ea28" && \
    pip install "ray[default,serve]==2.49.1"

RUN git clone https://github.com/invergent-ai/axolotl.git && \
    cd axolotl && \
    pip install -r requirements.txt && \
    pip install --no-build-isolation -e .[deepspeed,flash-attn,ring-flash-attn,optimizers,ray]

RUN mkdir -p /opt/densemax/eval && \
    conda create -n eval python=3.12.3 -y
SHELL ["conda", "run", "-n", "eval", "/bin/bash", "-c"]
WORKDIR /opt/densemax/eval
RUN pip install -U deepeval && \
    pip install deepteam

WORKDIR /opt/densemax

RUN curl -o /usr/bin/lakectl https://densemax.s3.eu-central-1.amazonaws.com/lakectl && \
    chmod +x /usr/bin/lakectl

# Cleanup
RUN rm /opt/vllm-0.11.0rc2.dev70+ge47433b3c.d20250930.cu129-cp38-abi3-linux_x86_64.whl && \
    rm /opt/xformers-0.0.33+5146f2ab.d20250930-cp39-abi3-linux_x86_64.whl && \
    rm /opt/flashinfer_python-0.3.1-cp39-abi3-linux_x86_64.whl && \
    rm /opt/torch-2.8.0a0+5228986c39.nv25.6-cp312-cp312-linux_x86_64.whl && \
    rm -rf /opt/pytorch && \
    rm -rf /usr/local/lib/python3.12/dist-packages && \
    rm -rf /root/.cache/pip && \
    apt-get clean

# Custom scripts (keep this section at the end for easy image updates)
COPY train/* /opt/densemax/train
RUN chmod a+x /opt/densemax/train/train.sh

COPY quant/* /opt/densemax/quant
RUN chmod a+x /opt/densemax/quant/quantize.sh

