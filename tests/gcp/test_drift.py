"""Drift tests (QA-7). State instance counts must match live counts.

State uses for_each blocks, so drift is count-based: extra live items
are orphans, fewer live items are missing. Name-level drift is covered
by endpoint tests.
Run: floci-pyenv/bin/python -m pytest tests/gcp -q
"""
import json
import os
import unittest

from common import get_json, emulator_up

STATE_ROOT = os.environ.get("STATE_ROOT", ".state/dev/gcp")

# live endpoint -> (state stack, state type, live list keys)
MAPPED = {
    "/storage/v1/b?project={project}": ("bootstrap", "google_storage_bucket", ("items",)),
    "/sql/v1beta4/projects/{project}/instances": ("stateful", "google_sql_database_instance", ("items",)),
    "/v1/projects/{project}/topics": ("stateful", "google_pubsub_topic", ("topics",)),
    "/v1/projects/{project}/secrets": ("stateful", "google_secret_manager_secret", ("secrets",)),
    "/v1/projects/{project}/subscriptions": ("stateful", "google_pubsub_subscription", ("subscriptions",)),
}


def state_instances(stack, rtype):
    path = os.path.join(STATE_ROOT, stack, "terraform.tfstate")
    with open(path) as f:
        data = json.load(f)
    return sum(len(r.get("instances", [])) for r in data.get("resources", [])
               if r.get("type") == rtype)


@unittest.skipUnless(emulator_up(), "emulator unreachable")
class TestDrift(unittest.TestCase):
    def test_counts_match(self):
        for endpoint, (stack, rtype, keys) in MAPPED.items():
            with self.subTest(endpoint=endpoint):
                live = get_json(endpoint)
                n_live = sum(len(live[k]) for k in keys if isinstance(live.get(k), list))
                n_state = state_instances(stack, rtype)
                self.assertEqual(n_live, n_state,
                                 f"drift: live={n_live} state={n_state} for {rtype}")


if __name__ == "__main__":
    unittest.main()
