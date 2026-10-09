"""Emulator endpoint tests (ported from helper-pg/verify_endpoints.py).

Run: floci-pyenv/bin/python -m unittest discover -s tests/gcp -v
"""
import unittest

from common import emulator_up, get_json, count_list

# name -> (path, minimum expected items; None = shape-only check)
ENDPOINTS = {
    "buckets": ("/storage/v1/b?project={project}", 1),
    "keyrings": ("/v1/projects/{project}/locations/us-central1/keyRings", 1),
    "cryptokeys": ("/v1/projects/{project}/locations/us-central1/keyRings/smartcloud-key/cryptoKeys", 1),
    "networks": ("/compute/v1/projects/{project}/global/networks", 1),
    "subnetworks": ("/compute/v1/projects/{project}/regions/us-central1/subnetworks", 1),
    "firewalls": ("/compute/v1/projects/{project}/global/firewalls", 1),
    "services": ("/v1/projects/{project}/services", 1),
    "serviceaccounts": ("/v1/projects/{project}/serviceAccounts", 1),
    "secrets": ("/v1/projects/{project}/secrets", 1),
    "topics": ("/v1/projects/{project}/topics", 1),
    "subscriptions": ("/v1/projects/{project}/subscriptions", 1),
    "sql": ("/sql/v1beta4/projects/{project}/instances", 1),
    "run": ("/v2/projects/{project}/locations/us-central1/services", 1),
    "clusters": ("/container/v1/projects/{project}/locations/us-central1/clusters", 1),
    "datasets": ("/bigquery/v2/projects/{project}/datasets", 0),
    "bucket_objects": ("/storage/v1/b/smartcloud-frontend-static/o?project={project}", 0),
}

COUNT_KEYS = ("items", "topics", "secrets", "accounts", "services", "keyRings",
              "clusters", "subscriptions", "cryptoKeys")


@unittest.skipUnless(emulator_up(), "emulator unreachable")
class TestInfo(unittest.TestCase):
    def test_info(self):
        data = get_json("/_floci-gcp/info")
        self.assertIn("version", data)
        self.assertIn("port", data)


@unittest.skipUnless(emulator_up(), "emulator unreachable")
class TestEndpoints(unittest.TestCase):
    def test_all_endpoints(self):
        for name, (path, minimum) in ENDPOINTS.items():
            with self.subTest(endpoint=name):
                data = get_json(path)
                n = count_list(data, *COUNT_KEYS)
                self.assertGreaterEqual(n, minimum, f"{name} has {n} items")


if __name__ == "__main__":
    unittest.main()
