FROM pytorch/pytorch:2.8.0-cuda12.8-cudnn9-devel

RUN apt update && apt install -y nginx git curl git-lfs \
    && rm -rf /var/lib/apt/lists/*

COPY nginx.conf /etc/nginx/nginx.conf
COPY start.sh /start.sh
RUN chmod +x /start.sh

WORKDIR /workspace

CMD ["/start.sh"]