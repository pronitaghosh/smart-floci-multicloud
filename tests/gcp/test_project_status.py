"""Project status tests (ported from helper-pg/verify_status.py).

Covers terraform state per stack, docker sidecars, and Block 6 workloads.
Block 6 tests fail until workloads are deployed; that is intentional.

Run: floci-pyenv/bin/python -m unittest discover -s tests/gcp -v
Env: FLOCI_GCP_BASE, FLOCI_GCP_PROJECT, STATE_ROOT, OVERLAY_DIR,
     NAMESPACE, GATEWAY_URL (defaults target this repo layout).
"""
import json
import os
import subprocess
import unittest
import urllib.request
import urllib.error

from common import BASE, PROJECT, TIMEOUT, emulator_up

STATE_ROOT = os.environ.get("STATE_ROOT", ".state/dev/gcp")
OVERLAY_DIR = os.environ.get("OVERLAY_DIR", "k8s/gcp")
NAMESPACE = os.environ.get("NAMESPACE", "smartcloud")
GATEWAY_URL = os.environ.get("GATEWAY_URL", "http://localhost:30080/healthz")

EXPECTED_TYPES = {
    "bootstrap": {"google_storage_bucket", "google_kms_key_ring",
                  "google_compute_network", "google_project_service"},
    "iam": {"google_service_account"},
    "stateful": {"google_sql_database_instance", "google_pubsub_topic",
                 "google_secret_manager_secret"},
    "standard": {"google_container_cluster", "google_cloud_run_v2_service"},
}

WORKLOADS = ("gateway", "user", "order", "payment")


def load_state(stack):
    path = os.path.join(STATE_ROOT, stack, "terraform.tfstate")
    assert os.path.exists(path), f"missing {path}"
    with open(path) as f:
        return json.load(f)


def kubectl(*args):
    try:
        p = subprocess.run(["kubectl", *args, "-o", "json"],
                           capture_output=True, text=True, timeout=15)
    except FileNotFoundError:
        raise unittest.SkipTest("kubectl not found")
    self_assert = p.returncode == 0
    assert self_assert, f"kubectl {' '.join(args)}: {(p.stderr or p.stdout).strip()[:200]}"
    return json.loads(p.stdout)


class TestStateFiles(unittest.TestCase):
    def test_all_stacks(self):
        for stack, expected in EXPECTED_TYPES.items():
            with self.subTest(stack=stack):
                data = load_state(stack)
                types = {r.get("type", "?") for r in data.get("resources", [])}
                self.assertTrue(data.get("resources"), f"{stack} has no resources")
                self.assertTrue(expected <= types,
                                f"{stack} missing {expected - types}")


class TestDocker(unittest.TestCase):
    def test_sidecars(self):
        try:
            p = subprocess.run(["docker", "ps", "--format", "{{.Names}}"],
                               capture_output=True, text=True, timeout=10)
        except FileNotFoundError:
            raise unittest.SkipTest("docker not found")
        self.assertEqual(p.returncode, 0, "docker ps failed")
        names = p.stdout
        for want in ("floci-gcp", "floci-gcp-cloudsql",
                     "floci-gcp-cloudrun", "floci-gcp-gke"):
            with self.subTest(container=want):
                self.assertIn(want, names, f"{want} not running")


@unittest.skipUnless(emulator_up(), "emulator unreachable")
class TestWorkloads(unittest.TestCase):
    """Block 6 acceptance. Fails until workloads are deployed."""

    def test_overlay_manifests(self):
        self.assertTrue(os.path.isdir(OVERLAY_DIR), f"missing {OVERLAY_DIR}")
        files = os.listdir(OVERLAY_DIR)
        for w in WORKLOADS:
            with self.subTest(workload=w):
                self.assertTrue(any(w in f for f in files),
                                f"no {w} manifest in {OVERLAY_DIR}")

    def test_namespace_exists(self):
        data = kubectl("get", "namespace", NAMESPACE)
        self.assertEqual(data["metadata"]["name"], NAMESPACE)

    def test_pods_ready(self):
        data = kubectl("get", "pods", "-n", NAMESPACE)
        items = data.get("items", [])
        self.assertTrue(items, "no pods in smartcloud")
        for pod in items:
            with self.subTest(pod=pod["metadata"]["name"]):
                phase = pod.get("status", {}).get("phase")
                if phase == "Succeeded":
                    continue  # completed job, not a serving pod
                statuses = pod.get("status", {}).get("containerStatuses", [])
                self.assertTrue(statuses, "no container statuses")
                self.assertTrue(all(c.get("ready") for c in statuses),
                                "pod not ready")

    def test_gateway_reachable(self):
        try:
            with urllib.request.urlopen(GATEWAY_URL, timeout=TIMEOUT) as r:
                self.assertEqual(r.status, 200, f"gateway {GATEWAY_URL}")
        except Exception as e:
            self.fail(f"gateway {GATEWAY_URL} unreachable: {e}")

    def test_argocd_synced(self):
        data = kubectl("get", "application", "smartcloud", "-n", "argocd")
        items = data.get("items", [data]) if "items" in data else [data]
        status = items[0].get("status", {})
        self.assertEqual(status.get("sync", {}).get("status"), "Synced")
        self.assertEqual(status.get("health", {}).get("status"), "Healthy")

    def test_rendered_config_not_tracked(self):
        p = subprocess.run(["git", "ls-files", "k8s/01-config.yaml"],
                           capture_output=True, text=True, timeout=10)
        self.assertEqual(p.stdout.strip(), "",
                         "rendered secret config is git-tracked")


if __name__ == "__main__":
    unittest.main()
