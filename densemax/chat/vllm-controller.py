import subprocess, threading, requests, os, signal, time
from fastapi import FastAPI, Request, Response
from fastapi.responses import JSONResponse, StreamingResponse
import sys

app = FastAPI(title="vLLM Proxy Controller")

# --- Configuration ---
MODEL_PATH = "/opt/work/model"
LORA_PATH = "/opt/work/outputs/lora"
VLLM_PORT = 8000
VLLM_URL = f"http://127.0.0.1:{VLLM_PORT}"
VLLM_PROC = None

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
        "--max-model-len", "8000",
        "-tp", "4",
        "--enforce-eager",
        "--model", MODEL_PATH,
        "--enable-lora",
        f"--lora-modules", f"sql-lora={LORA_PATH}",
        "--port", str(VLLM_PORT),
        "--host", "0.0.0.0"
    ]

    # Launch in background thread
    def run_vllm():
        global VLLM_PROC
        VLLM_PROC = subprocess.Popen(
            cmd,
            stdout=sys.stdout,
            stderr=sys.stderr,
        )
        VLLM_PROC.wait()

    threading.Thread(target=run_vllm, daemon=True).start()

    # Wait briefly to let server start
    time.sleep(10)
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
