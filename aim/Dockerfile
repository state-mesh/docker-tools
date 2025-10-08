FROM python:3.7

RUN pip install --upgrade aim

RUN mkdir /aim

ENTRYPOINT ["/bin/sh", "-c"]

CMD ["echo \"N\" | aim init --repo /aim && aim up --host 0.0.0.0 --port 43800 --workers 2 --repo /aim"]
