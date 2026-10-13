#!/usr/bin/env python3
"""Run a verification process with a bounded lifetime and process-group cleanup."""
import os, signal, subprocess, sys
seconds = int(sys.argv[1])
proc = subprocess.Popen(sys.argv[2:], start_new_session=True)
try:
    sys.exit(proc.wait(timeout=seconds))
except subprocess.TimeoutExpired:
    os.killpg(proc.pid, signal.SIGTERM)
    try: proc.wait(timeout=3)
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, signal.SIGKILL)
        proc.wait()
    print(f"Verification exceeded {seconds} seconds.", file=sys.stderr)
    sys.exit(124)
