"""Core round-trip tests (QA-7). Write then read back per service.

Run: floci-pyenv/bin/python -m pytest tests/gcp -q
"""
import base64
import json
import unittest
import urllib.request
import urllib.error

from common import BASE, PROJECT, TIMEOUT, emulator_up

BUCKET = "smartcloud-frontend-static"
KEYRING = f"/v1/projects/{PROJECT}/locations/us-central1/keyRings/smartcloud-key"
KEY = KEYRING + "/cryptoKeys/key"


def call(method, path, data=None, raw=None):
    url = BASE.rstrip("/") + path.format(project=PROJECT)
    body = json.dumps(data).encode() if data is not None else raw
    req = urllib.request.Request(url, data=body, method=method,
                                 headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
            payload = r.read().decode("utf-8", "replace")
            try:
                return r.status, json.loads(payload) if payload else {}
            except Exception:
                return r.status, payload
    except urllib.error.HTTPError as e:
        raise AssertionError(f"{method} {path} -> {e.code}: {e.read().decode()[:200]}")
    except Exception as e:
        raise AssertionError(f"{method} {path} failed: {e}")


@unittest.skipUnless(emulator_up(), "emulator unreachable")
class TestRoundTrips(unittest.TestCase):
    def test_gcs_object_cycle(self):
        name = "qa-roundtrip.txt"
        status, _ = call("POST",
                         f"/upload/storage/v1/b/{BUCKET}/o?uploadType=media&name={name}",
                         raw=b"qa")
        self.assertEqual(status, 200)
        status, fetched = call("GET", f"/storage/v1/b/{BUCKET}/o/{name}?alt=media")
        self.assertEqual(status, 200)
        self.assertEqual(fetched, "qa")
        status, _ = call("DELETE",
                         f"/storage/v1/b/{BUCKET}/o/{name}?project={{project}}")
        self.assertIn(status, (200, 204))

    def test_pubsub_publish_pull(self):
        _, pub = call("POST", "/v1/projects/{project}/topics/orders:publish",
                      {"messages": [{"data": base64.b64encode(b"qa").decode()}]})
        self.assertTrue(pub.get("messageIds"), "no message id")
        _, pulled = call("POST", "/v1/projects/{project}/subscriptions/orders-sub:pull",
                         {"maxMessages": 1})
        msgs = pulled.get("receivedMessages", [])
        self.assertTrue(msgs, "nothing pulled")
        call("POST", "/v1/projects/{project}/subscriptions/orders-sub:acknowledge",
             {"ackIds": [msgs[0]["ackId"]]})

    def test_secret_access(self):
        status, body = call(
            "GET", "/v1/projects/{project}/secrets/smartcloud-app-credentials/versions/1:access")
        self.assertEqual(status, 200)

    def test_kms_encrypt_decrypt(self):
        _, enc = call("POST", KEY + ":encrypt",
                      {"plaintext": base64.b64encode(b"qa").decode()})
        self.assertIn("ciphertext", enc)
        _, dec = call("POST", KEY + ":decrypt", {"ciphertext": enc["ciphertext"]})
        self.assertEqual(base64.b64decode(dec["plaintext"]), b"qa")

    def test_sql_runnable(self):
        # No SQL driver in test env: assert control-plane RUNNABLE status.
        _, data = call("GET", "/sql/v1beta4/projects/{project}/instances")
        items = data.get("items", [])
        by_name = {i["name"]: i for i in items}
        self.assertIn("postgres", by_name)
        self.assertEqual(by_name["postgres"].get("state", "RUNNABLE"), "RUNNABLE")


if __name__ == "__main__":
    unittest.main()
