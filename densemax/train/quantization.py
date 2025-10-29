import os
from datasets import load_dataset
from transformers import AutoModelForCausalLM, AutoTokenizer
from llmcompressor.modifiers.awq import AWQModifier
from llmcompressor import oneshot

model_dir = os.path.expandvars("$WORK_DIR/outputs/merged")
out_dir = os.path.expandvars("$WORK_DIR/outputs/quantized")
ds_dir = os.path.expandvars("$WORK_DIR/dataset")

model = AutoModelForCausalLM.from_pretrained(
    model_dir,
    device_map="auto",
    torch_dtype="auto",
    trust_remote_code=True
)
tokenizer = AutoTokenizer.from_pretrained(model_dir, trust_remote_code=True)
recipe = [AWQModifier(scheme="W4A16", targets=["Linear"], ignore=["lm_head"])]

def to_chat(example):
    text = example["text"] if "text" in example else str(example)
    return {
        "text": tokenizer.apply_chat_template(
            [{"role": "user", "content": text}],
            tokenize=False,
        )
    }

ds = load_dataset(ds_dir, split=f"train[:256]").shuffle(seed=42)
keep_cols = ["text"] if "text" in ds.column_names else ds.column_names
ds = ds.map(to_chat, remove_columns=[c for c in keep_cols if c != "text"])

oneshot(
    model=model,
    dataset=ds,
    recipe=recipe,
    max_seq_length=2048,
    num_calibration_samples=256
)

model.save_pretrained(out_dir, save_compressed=True)
tokenizer.save_pretrained(out_dir)

