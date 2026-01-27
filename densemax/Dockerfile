FROM nvcr.io/nvidia/cuda:12.9.1-cudnn-devel-ubuntu24.04

ENV UV_HTTP_TIMEOUT=500
ENV UV_INDEX_STRATEGY="unsafe-best-match"
ENV UV_LINK_MODE=symlink
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y gettext pybind11-dev cmake libwebp-dev curl unzip fuse3 git python3 pipx \
    && curl -LsSf https://astral.sh/uv/install.sh | sh \
    && mv ~/.local/bin/uv /usr/local/bin/ \
    && mv ~/.local/bin/uvx /usr/local/bin/

RUN curl https://rclone.org/install.sh | bash

RUN curl -o /usr/bin/lakectl https://densemax.s3.eu-central-1.amazonaws.com/lakectl \
    && chmod +x /usr/bin/lakectl

# Quantization
RUN mkdir -p /opt/densemax/quant
WORKDIR /opt/densemax/quant
RUN uv venv --python 3.12
RUN uv pip install "torch==2.9.1+cu129" "torchvision==0.24.1+cu129" "torchaudio==2.9.1+cu129" --index-url https://download.pytorch.org/whl/cu129 \
    && uv pip install "llmcompressor==0.9.0.1" --torch-backend=auto

## Serving
ENV VLLM_COMMIT=b2e65cb4a7ea7c000517a7b78a6e0ccd9ecb0517
WORKDIR /opt/densemax/serve
RUN uv venv --python 3.12
RUN uv pip install "torch==2.9.1+cu129" "torchvision==0.24.1+cu129" "torchaudio==2.9.1+cu129" --index-url https://download.pytorch.org/whl/cu129 \
    && uv pip install vllm --torch-backend=auto \
    && uv pip install "ray[default,serve]==2.50.1" \
    && uv pip install lmcache "nixl >= 0.6.0"

RUN git clone --depth=1 https://github.com/vllm-project/production-stack.git \
    && cd production-stack \
    && uv pip install -U setuptools_scm \
    && uv pip install -e .[semantic_cache] \
    && uv pip install lmcache==0.3.11

## Training with Surogate
WORKDIR /opt/densemax/train
RUN uv venv --python 3.12
RUN uv pip install wandb aim envsubst "ray==2.50.1" \
    && uv pip install "torch==2.9.1+cu129" "torchvision==0.24.1+cu129" "torchaudio==2.9.1+cu129" --index-url https://download.pytorch.org/whl/cu129 \
    && uv pip install https://github.com/invergent-ai/surogate/releases/download/v0.0.6/surogate-0.0.6+cu129-cp312-abi3-manylinux_2_39_x86_64.whl --torch-backend=auto

# Training with Axolotl
WORKDIR /opt/densemax/train-axolotl
RUN uv venv --python 3.12
RUN uv pip install "torch==2.8.0+cu129" "torchvision==0.23.0+cu129" --index-url https://download.pytorch.org/whl/cu129
RUN uv pip install https://github.com/Dao-AILab/flash-attention/releases/download/v2.8.3/flash_attn-2.8.3+cu12torch2.8cxx11abiTRUE-cp312-cp312-linux_x86_64.whl
RUN uv pip install wheel aim "cut-cross-entropy[transformers] @ git+https://github.com/axolotl-ai-cloud/ml-cross-entropy.git@147ea28" envsubst "ray[default,serve,tune]==2.50.1" "deepspeed==0.17.5"
RUN git clone --depth=1 https://github.com/invergent-ai/axolotl.git \
    && cd axolotl \
    && uv pip install -r requirements.txt \
    && uv pip install --no-build-isolation -e .[deepspeed,flash-attn,ring-flash-attn,optimizers,ray]
ADD https://densemax.s3.eu-central-1.amazonaws.com/base-image/bitsandbytes-0.48.1%2Binvergent-cp312-cp312-linux_x86_64.whl /opt/
RUN uv pip uninstall bitsandbytes \
    && uv pip install /opt/bitsandbytes-0.48.1+invergent-cp312-cp312-linux_x86_64.whl

## Evaluation
WORKDIR /opt/densemax/eval
RUN uv venv --python 3.12

# Install Docker CLI for sandbox code execution
RUN curl -fsSL https://download.docker.com/linux/static/stable/x86_64/docker-24.0.7.tgz | \
    tar xz -C /usr/local/bin --strip-components=1 docker/docker

# Add surogate-eval
ARG SUROGATE_CACHE_BUST=18
RUN uv pip install "torch==2.9.0+cu129" "torchvision==0.24.0+cu129" "torchaudio==2.9.0+cu129" --index-url https://download.pytorch.org/whl/cu129 \
    && uv pip install "git+https://github.com/invergent-ai/surogate_eval.git@main#egg=surogate-eval[security,vision,rag]"

## Base env
RUN cd /opt/densemax && pipx install "ray[default,serve]==2.50.1" && ln -sf /root/.local/bin/ray /usr/local/bin/ray

# WeasyPrint dependencies for PDF generation and iproute2
RUN apt-get update && apt-get install -y \
    libglib2.0-0 \
    libpango-1.0-0 \
    libpangocairo-1.0-0 \
    libgdk-pixbuf2.0-0 \
    libffi-dev \
    shared-mime-info \
    iproute2 \
    && rm -rf /var/lib/apt/lists/*

RUN rm -f /opt/*.whl \
    && rm -f /opt/*.deb \
    && rm -rf /opt/densemax/serve/production-stack \
    && apt-get clean

## Custom scripts (keep this section at the end for easy image updates)
RUN mkdir /scripts

COPY job-entry.sh /usr/bin/job-entry
COPY train/train.sh /usr/bin/train
COPY train/train-axolotl.sh /usr/bin/train-axolotl
COPY quant/quantization.py /scripts
COPY quant/quantize.sh /usr/bin/quantize
COPY eval/run_eval.sh /usr/bin/eval
COPY eval/generate_config.py /opt/densemax/eval/generate_config.py


RUN chmod a+x /usr/bin/job-entry \
    && chmod a+x /usr/bin/train* \
    && chmod a+x /usr/bin/quantize \
    && chmod a+x /usr/bin/eval

#https://github.com/NVIDIA/nccl/issues/1838
ENV NCCL_CUMEM_HOST_ENABLE=0
ENV TUNE_MAX_PENDING_TRIALS_PG=32
ENV RAY_RUNTIME_ENV_HOOK=ray._private.runtime_env.uv_runtime_env_hook.hook

ENV RCLONE_CONFIG_LAKEFS_TYPE=s3
ENV RCLONE_CONFIG_LAKEFS_PROVIDER=Other
ENV RCLONE_CONFIG_LAKEFS_ENV_AUTH=false
ENV RCLONE_CONFIG_NO_CHECK_BUCKET=true
ENV RCLONE_NO_CHECK_CERTIFICATE=true
ENV RCLONE_CONFIG_LAKEFS_ENDPOINT=http://lakefs-s3.statemesh.svc

# ------------------------------------------------------------
# vLLM fastAPI controller for external model testing
# ------------------------------------------------------------
COPY chat/vllm-controller.py /opt/densemax/serve/vllm-controller.py
EXPOSE 9000

ENTRYPOINT ["/bin/bash","-c"]

