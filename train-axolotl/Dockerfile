############################
# Builder: create axolotl venv
############################
FROM nvcr.io/nvidia/cuda:12.9.1-cudnn-devel-ubuntu24.04 AS builder

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

WORKDIR /opt/densemax/train-axolotl
RUN uv venv --seed --python 3.12

# Torch cu129 (as in your original axolotl section)
RUN uv pip install \
    "torch==2.8.0+cu129" "torchvision==0.23.0+cu129" \
    --index-url https://download.pytorch.org/whl/cu129

# flash-attn wheel
RUN uv pip install \
    https://github.com/Dao-AILab/flash-attention/releases/download/v2.8.3/flash_attn-2.8.3+cu12torch2.8cxx11abiTRUE-cp312-cp312-linux_x86_64.whl

# Axolotl deps
RUN uv pip install \
    wheel aim envsubst \
    "cut-cross-entropy[transformers] @ git+https://github.com/axolotl-ai-cloud/ml-cross-entropy.git@147ea28" \
    "ray[default,serve,tune]==2.50.1" \
    "deepspeed==0.17.5"

# Axolotl
RUN git clone --depth=1 https://github.com/invergent-ai/axolotl.git /opt/densemax/train-axolotl/axolotl \
    && uv pip install -r /opt/densemax/train-axolotl/axolotl/requirements.txt \
    && uv pip install --no-build-isolation -e /opt/densemax/train-axolotl/axolotl[deepspeed,flash-attn,ring-flash-attn,optimizers,ray]

# Custom bitsandbytes wheel
ADD https://densemax.s3.eu-central-1.amazonaws.com/base-image/bitsandbytes-0.48.1%2Binvergent-cp312-cp312-linux_x86_64.whl /tmp/bitsandbytes-0.48.1+invergent-cp312-cp312-linux_x86_64.whl
RUN uv pip uninstall bitsandbytes || true \
    && uv pip install /tmp/bitsandbytes-0.48.1+invergent-cp312-cp312-linux_x86_64.whl \
    && rm -f /tmp/bitsandbytes-0.48.1+invergent-cp312-cp312-linux_x86_64.whl


RUN /opt/densemax/train-axolotl/.venv/bin/axolotl --help >/dev/null


############################
# Runtime: minimal
############################
FROM nvcr.io/nvidia/cuda:12.9.1-cudnn-runtime-ubuntu24.04 AS runtime
ENV DEBIAN_FRONTEND=noninteractive

# Minimal OS deps to run python venv + native wheels
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash ca-certificates \
    python3.12 \
    libstdc++6 libgcc-s1 libgomp1 \
    libffi8 libssl3 zlib1g \
    libbz2-1.0 liblzma5 \
    libsqlite3-0 libreadline8 \
    libuuid1 \
    && rm -rf /var/lib/apt/lists/*

# Layout expected by job-entry-sky.sh and train-sky-axolotl.sh
RUN mkdir -p /opt/densemax/train-axolotl

COPY --from=builder /opt/densemax/train-axolotl/.venv /opt/densemax/train-axolotl/.venv
COPY --from=builder /opt/densemax/train-axolotl/axolotl /opt/densemax/train-axolotl/axolotl

# Scripts
COPY job-entry-sky.sh /usr/bin/job-entry-sky
COPY train/sky/train-sky-axolotl.sh /usr/bin/train-sky-axolotl

RUN mkdir -p /root/sky_templates/ray
COPY train/sky/templates/start_cluster /root/sky_templates/ray/start_cluster
COPY train/sky/templates/stop_cluster /root/sky_templates/ray/stop_cluster

RUN chmod a+x /usr/bin/job-entry* \
    && chmod a+x /usr/bin/train* \
    && chmod a+x /root/sky_templates/ray/start_cluster \
    && chmod a+x /root/sky_templates/ray/stop_cluster

ENTRYPOINT ["/bin/bash","-c"]
