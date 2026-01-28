import subprocess, threading, requests, os, signal, time, sys
from fastapi import FastAPI, Request, Response
from fastapi.responses import JSONResponse, StreamingResponse
from pathlib import Path

app = FastAPI(title="vLLM Proxy Controller")

# --- Configuration ---
MODEL_PATH = "/opt/work/model"
OUTPUT_PATH = "/opt/work/outputs"
LORA_PATH = OUTPUT_PATH + "/lora"
MERGED_PATH = OUTPUT_PATH + "/merged"

VLLM_PORT = 8000
VLLM_URL = f"http://127.0.0.1:{VLLM_PORT}"
VLLM_PROC = None
VLLM_TP = os.getenv("VLLM_TP", "1")
LORA = os.getenv("LORA", "false")
MERGED = os.getenv("MERGE_LORA", "false")

# --- Start endpoint ---
@app.post("/start")
def start_vllm():
    """Start the vLLM OpenAI-compatible API server if not already running."""
    global VLLM_PROC
    if VLLM_PROC and VLLM_PROC.poll() is None:
        return {"status": "already running", "pid": VLLM_PROC.pid}

    cmd = [
        "python", "-m", "vllm.entrypoints.openai.api_server",
        "--dtype", "half",
        "--max-model-len", "8192",
        "-tp", VLLM_TP,
        "--port", str(VLLM_PORT),
        "--host", "0.0.0.0"
    ]

    if MERGED.lower() == "true":
        resolved_merged_path = (
            MERGED_PATH if is_valid_merged_model(MERGED_PATH) else OUTPUT_PATH
        )
        cmd += [
            "--model", resolved_merged_path
        ]
        print(f"Serving merged model from path {resolved_merged_path}")
    else:
        if LORA.lower() == "true":
            resolved_lora_path = (
                LORA_PATH if is_valid_lora(LORA_PATH) else OUTPUT_PATH
            )
            cmd += [
                "--model", MODEL_PATH,
                "--enable-lora",
                "--max-lora-rank", "256",
                f"--lora-modules", f"test-lora={resolved_lora_path}"
            ]
            print(f"Serving lora adapter from path {resolved_lora_path} on base model from path {MODEL_PATH}")
        else:
            cmd += [
                "--model", OUTPUT_PATH
            ]
            print(f"Serving fully trained model from path {OUTPUT_PATH}")



    def run_vllm():
        global VLLM_PROC
        VLLM_PROC = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1
        )

        for line in VLLM_PROC.stdout:
            sys.stdout.write(line)
            sys.stdout.flush()
            if "Application startup complete" in line:
                server_ready_event.set()

        VLLM_PROC.wait()

    server_ready_event = threading.Event()
    threading.Thread(target=run_vllm, daemon=True).start()

    # Wait until we see the ready message (timeout for safety)
    if not server_ready_event.wait(timeout=600):
        raise TimeoutError("vLLM failed to start within 600 seconds")
    return {"status": "started", "cmd": " ".join(cmd)}


# --- Stop endpoint ---
@app.post("/stop")
def stop_vllm():
    global VLLM_PROC
    if not VLLM_PROC or VLLM_PROC.poll() is not None:
        return {"status": "not running"}
    os.kill(VLLM_PROC.pid, signal.SIGTERM)
    VLLM_PROC.wait(timeout=5)
    return {"status": "stopped"}


# --- Health check ---
@app.get("/status")
def status():
    running = VLLM_PROC and VLLM_PROC.poll() is None
    return {"running": running, "pid": VLLM_PROC.pid if running else None}


@app.api_route("/v1/{path:path}", methods=["GET", "POST", "PUT", "PATCH", "DELETE"])
async def proxy_vllm(path: str, request: Request):
    if not (VLLM_PROC and VLLM_PROC.poll() is None):
        return JSONResponse({"error": "vLLM server not running"}, status_code=503)

    url = f"{VLLM_URL}/v1/{path}"
    method = request.method
    headers = dict(request.headers)
    body = await request.body()

    headers.setdefault("Accept", "text/event-stream")
    try:
        r = requests.request(method, url, headers=headers, data=body, stream=True, timeout=None)
        ctype = r.headers.get("content-type", "")
        if ctype.startswith("text/event-stream"):
            def sse_generator():
                try:
                    for line in r.iter_lines(chunk_size=1, decode_unicode=True):
                        if line is None:
                            continue
                        yield (line + "\n")
                finally:
                    r.close()

            return StreamingResponse(
                sse_generator(),
                status_code=r.status_code,
                headers={
                    "Content-Type": "text/event-stream",
                    "Cache-Control": "no-cache",
                    "X-Accel-Buffering": "no",
                },
            )
        return Response(
            content=r.content,
            status_code=r.status_code,
            headers={"Content-Type": ctype or "application/json"},
        )

    except requests.RequestException as e:
        return JSONResponse({"error": str(e)}, status_code=500)

def is_valid_merged_model(path: str) -> bool:
    if not path:
        return False
    p = Path(path)
    if not p.exists():
        return False
    return (
            (p / "config.json").exists()
            and (p / "model.safetensors").exists()
    )

def is_valid_lora(path: str) -> bool:
    if not path:
        return False
    p = Path(path)
    if not p.exists():
        return False
    return (
            (p / "adapter_config.json").exists()
            and (p / "adapter_model.safetensors").exists()
    )

