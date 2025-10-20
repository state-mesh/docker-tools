FROM nvcr.io/nvidia/pytorch:25.06-py3

RUN curl -o /usr/bin/lakectl https://densemax.s3.eu-central-1.amazonaws.com/lakectl \
    && chmod +x /usr/bin/lakectl

COPY common/* /opt/nvidia/entrypoint.d
RUN sed -i '/torch==/d' /etc/pip/constraint.txt
RUN sed -i '/torchvision==/d' /etc/pip/constraint.txt

RUN pip uninstall -y torch torchvision torchaudio \
    && pip install "torch==2.8.0+cu129" "torchvision==0.23.0+cu129" --index-url https://download.pytorch.org/whl/cu129 \
    && pip install aim "cut-cross-entropy[transformers] @ git+https://github.com/axolotl-ai-cloud/ml-cross-entropy.git@147ea28"

WORKDIR /opt/densemax/train

RUN git clone --depth=1 https://github.com/invergent-ai/axolotl.git \
    && cd axolotl \
    && pip install -r requirements.txt \
    && pip install --no-build-isolation -e .[deepspeed,flash-attn,ring-flash-attn,optimizers,ray] \
    && pip install --no-cache-dir "ray[default,serve,tune]==2.50.1" \
    && pip install envsubst

RUN apt-get update && apt-get install -y curl unzip && apt-get clean
RUN curl https://rclone.org/install.sh | bash

ADD https://densemax.s3.eu-central-1.amazonaws.com/base-image/bitsandbytes-0.48.1%2Binvergent-cp312-cp312-linux_x86_64.whl /opt/
RUN pip uninstall -y bitsandbytes \
    && pip install /opt/bitsandbytes-0.48.1+invergent-cp312-cp312-linux_x86_64.whl

RUN rm -f /opt/*.whl \
    && rm -f /opt/*.deb \
    && rm -rf /opt/pytorch \
    && rm -rf /root/.cache/pip \
    && apt-get clean

# Custom scripts (keep this section at the end for easy image updates)
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

ENV TUNE_MAX_PENDING_TRIALS_PG=32

ENTRYPOINT ["/bin/bash","-c","--"]


