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
ADD https://github.com/conda-forge/miniforge/releases/download/25.3.1-0/Miniforge3-25.3.1-0-Linux-x86_64.sh /opt
RUN sh ./Miniforge3-Linux-x86_64.sh -b -p /opt/miniforge && \
    rm ./Miniforge3-Linux-x86_64.sh && \
    conda init

# Quantization
RUN cd /opt/densemax/quant && conda create -n quant python=3.12.11 -y
SHELL ["conda", "run", "-n", "quant", "/bin/bash", "-c"]
RUN pip install /opt/torch-2.8.0a0+5228986c39.nv25.6-cp312-cp312-linux_x86_64.whl "llmcompressor==0.8.0"

# Serving
ADD https://densemax.s3.eu-central-1.amazonaws.com/base-image/vllm-0.11.0rc2.dev356%2Bge246ad6f0.d20251010.cu129-cp38-abi3-linux_x86_64.whl /opt
ADD https://densemax.s3.eu-central-1.amazonaws.com/base-image/xformers-0.0.33%2Bf2043594.d20251009-cp39-abi3-linux_x86_64.whl /opt
RUN cd /opt/densemax/serve && conda create -n serve python=3.12.11 -y
SHELL ["conda", "run", "-n", "serve", "/bin/bash", "-c"]
RUN sed -i '/nvidia-cudnn-frontend/d' /etc/pip/constraint.txt
RUN pip install /opt/torch-2.8.0a0+5228986c39.nv25.6-cp312-cp312-linux_x86_64.whl && \
    pip install /opt/xformers-0.0.33+f2043594.d20251009-cp39-abi3-linux_x86_64.whl && \
    pip install /opt/vllm-0.11.0rc2.dev356+ge246ad6f0.d20251010.cu129-cp38-abi3-linux_x86_64.whl && \
    pip install "triton==3.3.1" "flashinfer-python==0.4.0" "flashinfer-cubin==0.4.0" && \
    pip install "flashinfer-jit-cache==0.4.0" --extra-index-url https://flashinfer.ai/whl/cu$(echo $CUDA_VERSION | cut -d. -f1,2 | tr -d '.') && \
    pip uninstall -y pynvml

# Training
ADD https://densemax.s3.eu-central-1.amazonaws.com/base-image/flash_attn-2.8.3-cp312-cp312-linux_x86_64.whl /opt
RUN cd /opt/densemax/train && conda create -n train python=3.12.11 -y
SHELL ["conda", "run", "-n", "train", "/bin/bash", "-c"]
WORKDIR /opt/densemax/train
RUN pip install /opt/torch-2.8.0a0+5228986c39.nv25.6-cp312-cp312-linux_x86_64.whl && \
    pip install aim && \
    pip install /opt/xformers-0.0.33+f2043594.d20251009-cp39-abi3-linux_x86_64.whl && \
    pip install /opt/flash_attn-2.8.3-cp312-cp312-linux_x86_64.whl && \
    pip install "cut-cross-entropy[transformers] @ git+https://github.com/axolotl-ai-cloud/ml-cross-entropy.git@147ea28"

RUN git clone --depth=1 https://github.com/invergent-ai/axolotl.git && \
    cd axolotl && \
    pip install -r requirements.txt && \
    pip install --no-build-isolation -e .[deepspeed,flash-attn,ring-flash-attn,optimizers,ray] && \
    pip install --no-cache-dir "ray[default,serve,tune]==2.49.1"

RUN mkdir -p /opt/densemax/eval && \
    conda create -n eval python=3.12.1 -y
SHELL ["conda", "run", "-n", "eval", "/bin/bash", "-c"]
WORKDIR /opt/densemax/eval
RUN pip install -U deepeval && \
    pip install deepteam

SHELL ["conda", "run", "-n", "base", "/bin/bash", "-c"]
WORKDIR /opt/densemax
RUN pip install --no-cache-dir "ray[default,serve]==2.49.1"

RUN curl -o /usr/bin/lakectl https://densemax.s3.eu-central-1.amazonaws.com/lakectl && \
    chmod +x /usr/bin/lakectl

# Cleanup
RUN rm /opt/*.whl && \
    rm -rf /opt/pytorch && \
    rm -rf /usr/local/lib/python3.12/dist-packages && \
    rm -rf /root/.cache/pip && \
    apt-get clean

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