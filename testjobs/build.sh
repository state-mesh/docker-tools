#!/bin/bash

docker build -t statemesh/test-job:1.0 .
docker push statemesh/test-job:1.0
