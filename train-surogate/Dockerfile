FROM ghcr.io/invergent-ai/surogate:latest-cu128

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
