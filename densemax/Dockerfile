FROM nvcr.io/nvidia/pytorch:25.06-py3

ENV CONDA_DIR=/opt/miniforge
ENV PATH=$CONDA_DIR/bin:$PATH

RUN apt-get update && apt-get install -y gettext pybind11-dev cmake libwebp-dev curl unzip \
    && pip uninstall -y torch torchvision torchaudio distributed-ucxx pylibcudf cudf cupy-cuda12x numba thinc pyarrow numpy dask-cuda cuml cugraph-service-server nx-cugraph distributed-ucx pylibcugraph cugraph kvikio dask-cudf librosa spacy onnx tensorboard \
    && mkdir -p /opt/densemax/{quant,train,serve,eval} \
    && curl -LsSf https://astral.sh/uv/install.sh | sh \
    && mv ~/.local/bin/uv /usr/local/bin/ \
    && mv ~/.local/bin/uvx /usr/local/bin/

RUN curl https://rclone.org/install.sh | bash

COPY common/* /opt/nvidia/entrypoint.d
RUN sed -i '/torch==/d' /etc/pip/constraint.txt
RUN sed -i '/torchvision==/d' /etc/pip/constraint.txt

RUN curl -o /usr/bin/lakectl https://densemax.s3.eu-central-1.amazonaws.com/lakectl \
    && chmod +x /usr/bin/lakectl

# Quantization
WORKDIR /opt/densemax/quant
RUN uv venv --python 3.12
RUN uv pip install "torch==2.8.0+cu129" "torchvision==0.23.0+cu129" --index-url https://download.pytorch.org/whl/cu129 \
    && uv pip install "llmcompressor==0.8.1"

## Serving
WORKDIR /opt/densemax/serve
RUN uv venv --python 3.12
RUN uv pip install "torch==2.8.0+cu129" "torchvision==0.23.0+cu129" --index-url https://download.pytorch.org/whl/cu129 \
    && uv pip install -U vllm --torch-backend=auto --extra-index-url https://wheels.vllm.ai/latest

## Training
WORKDIR /opt/densemax/train
RUN uv venv --python 3.12 \
    && uv pip install "torch==2.8.0+cu129" "torchvision==0.23.0+cu129" --index-url https://download.pytorch.org/whl/cu129 \
    && uv pip install wheel aim "cut-cross-entropy[transformers] @ git+https://github.com/axolotl-ai-cloud/ml-cross-entropy.git@147ea28"

RUN git clone --depth=1 https://github.com/invergent-ai/axolotl.git \
    && cd axolotl \
    && uv pip install -r requirements.txt \
    && uv pip install --no-build-isolation -e .[deepspeed,flash-attn,ring-flash-attn,optimizers,ray] \
    && uv pip install --no-cache-dir "ray[default,serve,tune]==2.50.1" \
    && uv pip install envsubst

ADD https://densemax.s3.eu-central-1.amazonaws.com/base-image/bitsandbytes-0.48.1%2Binvergent-cp312-cp312-linux_x86_64.whl /opt/
RUN uv pip uninstall bitsandbytes \
    && uv pip install /opt/bitsandbytes-0.48.1+invergent-cp312-cp312-linux_x86_64.whl

## Evaluation
WORKDIR /opt/densemax/eval
RUN uv venv --python 3.12
RUN uv pip install -U deepeval deepteam

## Base env
RUN cd /opt/densemax && pip install --no-cache-dir "ray[default,serve]==2.50.1"

RUN rm -f /opt/*.whl \
    && rm -f /opt/*.deb \
    && rm -rf /opt/pytorch \
    && rm -rf /root/.cache/pip \
    && apt-get clean

RUN apt install iproute2 -y
## Custom scripts (keep this section at the end for easy image updates)
RUN mkdir /scripts

COPY train/quantization.py /scripts
COPY quant/quantize.py /scripts
COPY job-entry.sh /usr/bin/job-entry
COPY train/quant.sh /usr/bin/quant
COPY train/train.sh /usr/bin/train
COPY quant/quantize.sh /usr/bin/quantize

RUN chmod a+x /usr/bin/job-entry \
    && chmod a+x /usr/bin/quant \
    && chmod a+x /usr/bin/train \
    && chmod a+x /usr/bin/quantize

#https://github.com/NVIDIA/nccl/issues/1838
ENV NCCL_CUMEM_HOST_ENABLE=0
ENV TUNE_MAX_PENDING_TRIALS_PG=32
ENV RAY_RUNTIME_ENV_HOOK=ray._private.runtime_env.uv_runtime_env_hook.hook

# ------------------------------------------------------------
# vLLM fastAPI controller for external model testing
# ------------------------------------------------------------
COPY chat/vllm-controller.py /opt/densemax/serve/vllm-controller.py
EXPOSE 9000

ENTRYPOINT ["/bin/bash","-c"]

