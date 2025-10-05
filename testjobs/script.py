import os
from time import sleep

ENV_PARAM1 = "PARAM1"
ENV_PARAM2 = "PARAM2"
ENV_SLEEP = "SLEEP"


def run_job():
    param1 = os.getenv(ENV_PARAM1, "default1")
    param2 = os.getenv(ENV_PARAM2, "default2")
    sleepSec = os.getenv(ENV_SLEEP, "1")

    print(f"Running job with {ENV_PARAM1}={param1} and {ENV_PARAM2}={param2}...")
    print(f"ETA {sleepSec} seconds...")
    sleep(int(sleepSec))
    print('{"status": "success", "result1": "ok", "result2": 42}')

if __name__ == "__main__":
    run_job()
