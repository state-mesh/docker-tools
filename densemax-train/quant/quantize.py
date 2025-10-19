import argparse
import os

model_dir = os.path.expandvars("$WORK_DIR/$BASE_MODEL")
out_dir = os.path.expandvars("$WORK_DIR/quantized")
ds_dir = os.path.expandvars("$WORK_DIR/dataset")

