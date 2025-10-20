#!/bin/bash

conda activate quant

set -e

echo "Downloading model ${BASE_MODEL}"
lakectl fs download -r lakefs://$BASE_MODEL/ $WORK_DIR/model

echo "Downloading dataset ${DATASET}"
lakectl fs download -r lakefs://$DATASET/ $WORK_DIR/dataset

python quantize.py

echo "Uploading quantized model to hub"
lakectl branch create lakefs://$BASE_MODEL-$BRANCH -s lakefs://$BASE_MODEL
lakectl fs upload -rs $WORK_DIR/outputs/$BASE_MODEL/quantized/ lakefs://$BASE_MODEL-$BRANCH/


