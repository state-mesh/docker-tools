FROM infiniflow/ragflow:v0.19.1-slim

RUN apt install mysql-client -y

COPY nginx/nginx.conf /etc/nginx/nginx.conf
COPY nginx/proxy.conf /etc/nginx/proxy.conf
COPY nginx/ragflow.conf /etc/nginx/conf.d/ragflow.conf
COPY service_conf.yaml.template /ragflow/conf/service_conf.yaml.template

COPY entrypoint.sh ./
RUN chmod +x ./entrypoint.sh

ENTRYPOINT ["./entrypoint.sh"]