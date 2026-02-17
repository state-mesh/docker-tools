############################
# Builder: create Surogate venv (CUDA 12.8)
############################
FROM nvcr.io/nvidia/cuda:12.8.0-cudnn-devel-ubuntu24.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive
ENV UV_HTTP_TIMEOUT=500
ENV UV_INDEX_STRATEGY="unsafe-best-match"
ENV UV_LINK_MODE=copy

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl git \
    python3.12 python3.12-venv \
    && rm -rf /var/lib/apt/lists/*

RUN curl -LsSf https://astral.sh/uv/install.sh | sh \
    && mv /root/.local/bin/uv /usr/local/bin/uv \
    && mv /root/.local/bin/uvx /usr/local/bin/uvx

WORKDIR /opt/densemax/train
RUN uv venv --seed --python 3.12

# Your training-time python deps
RUN uv pip install wandb aim envsubst "ray==2.50.1"

# Torch cu128 (CUDA 12.8)
RUN uv pip install \
    "torch==2.9.1+cu128" "torchvision==0.24.1+cu128" "torchaudio==2.9.1+cu128" \
    --index-url https://download.pytorch.org/whl/cu128

# Surogate cu128 wheel
RUN uv pip install \
    https://github.com/invergent-ai/surogate/releases/download/v0.1.2/surogate-0.1.2+cu128-cp312-abi3-manylinux_2_39_x86_64.whl \
    --torch-backend=auto

RUN /opt/densemax/train/.venv/bin/python -c "import torch; import surogate; print(torch.__version__); print('surogate ok')"


############################
# Runtime: minimal
############################
FROM nvcr.io/nvidia/cuda:12.8.0-cudnn-runtime-ubuntu24.04 AS runtime

ENV DEBIAN_FRONTEND=noninteractive

RUN mkdir -p /opt/densemax/train \
 && mkdir -p /root/.triton/autotune /root/.triton/cache \
 && chmod -R 777 /root/.triton

COPY --from=builder /opt/densemax/train/.venv /opt/densemax/train/.venv

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash ca-certificates \
    python3.12 \
    libstdc++6 libgcc-s1 libgomp1 \
    libffi8 libssl3 zlib1g \
    libbz2-1.0 liblzma5 \
    libsqlite3-0 libreadline8 \
    libuuid1 \
    libglib2.0-0 libgl1 \
    && rm -rf /var/lib/apt/lists/*

ENV PATH="/opt/densemax/train/.venv/bin:${PATH}"
WORKDIR /opt/densemax/train

# Scripts
COPY job-entry-sky.sh /usr/bin/job-entry-sky
COPY train/sky/train-sky.sh /usr/bin/train-sky

RUN mkdir -p /root/sky_templates/ray
COPY train/sky/templates/start_cluster /root/sky_templates/ray/start_cluster
COPY train/sky/templates/stop_cluster /root/sky_templates/ray/stop_cluster

RUN chmod a+x /usr/bin/job-entry* \
    && chmod a+x /usr/bin/train* \
    && chmod a+x /root/sky_templates/ray/start_cluster \
    && chmod a+x /root/sky_templates/ray/stop_cluster

CMD ["sleep", "infinity"]
