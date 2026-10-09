"""Shared client for floci-gcp emulator tests (stdlib only).

Env:
  FLOCI_GCP_BASE     emulator base URL (default http://localhost:4588)
  FLOCI_GCP_PROJECT  project id (default floci-local)
"""
import json
import os
import urllib.request
import urllib.error

BASE = os.environ.get("FLOCI_GCP_BASE", "http://localhost:4588")
PROJECT = os.environ.get("FLOCI_GCP_PROJECT", "floci-local")
TIMEOUT = float(os.environ.get("FLOCI_GCP_TIMEOUT", "5"))


def get(path, timeout=TIMEOUT):
    url = BASE.rstrip("/") + path.format(project=PROJECT)
    try:
        with urllib.request.urlopen(url, timeout=timeout) as r:
            return r.status, r.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        return e.code, ""
    except Exception as e:
        raise AssertionError(f"GET {url} failed: {e}")


def get_json(path, timeout=TIMEOUT):
    status, body = get(path, timeout)
    assert status == 200, f"GET {path} status={status}"
    try:
        data = json.loads(body)
    except Exception as e:
        raise AssertionError(f"GET {path} not JSON: {e}")
    return data


def count_list(data, *keys):
    """Number of items under first present list key; 0 if none present."""
    if isinstance(data, dict):
        for k in keys:
            if k in data and isinstance(data[k], list):
                return len(data[k])
        if not any(isinstance(v, list) for v in data.values()):
            return 0
    if isinstance(data, list):
        return len(data)
    raise AssertionError(f"unexpected payload shape: {str(data)[:200]}")


def emulator_up():
    try:
        status, body = get("/_floci-gcp/info", timeout=TIMEOUT)
        return status == 200 and "version" in body
    except AssertionError:
        return False
