FROM axolotlai/axolotl:main-py3.11-cu128-2.8.0

USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
    tini curl wget iproute2 net-tools telnet iputils-ping gettext-base && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir "ray[default,serve]==2.49.1"
RUN pip install lakefs-spec
RUN pip install fbgemm-gpu-genai==1.3.0
RUN pip install llmcompressor

ENV PYTHONUNBUFFERED=1
RUN mkdir -p /opt/work
RUN mkdir /scripts

COPY train.sh /usr/bin/train
RUN chmod +x /usr/bin/train

COPY quantization.py /scripts

# Apply Axolotl code patches
# Patch for deepspeed config bug
COPY patch/utils/trainer.py /workspace/axolotl/src/axolotl/utils/trainer.py

ENTRYPOINT ["/bin/bash","-c","--"]
