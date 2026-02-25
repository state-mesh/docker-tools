FROM ghcr.io/invergent-ai/surogate:latest-cu128

USER root

RUN uv pip install aim

# Scripts
COPY job-entry-sky.sh /usr/bin/job-entry-sky
COPY train/sky/train-sky.sh /usr/bin/train-sky
COPY train/sky/metrics_reporter.py /usr/bin/metrics_reporter.py
COPY entrypoint.sh /usr/local/bin/entrypoint.sh

RUN mkdir -p /root/sky_templates/ray
COPY train/sky/templates/start_cluster /root/sky_templates/ray/start_cluster
COPY train/sky/templates/stop_cluster /root/sky_templates/ray/stop_cluster

RUN chmod a+x /usr/bin/job-entry* \
    && chmod a+x /usr/bin/train* \
    && chmod a+x /root/sky_templates/ray/start_cluster \
    && chmod a+x /root/sky_templates/ray/stop_cluster
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["sleep","infinity"]
