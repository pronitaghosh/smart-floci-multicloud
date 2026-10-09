"""Reconcile tests (QA-7). Observed state must match the planned table.

Source: docs/gcp-floci-implementation-plan.md resource mapping table
(core only; stretch excluded). Counts are resource instances per type.
Deviations carry reasons in EXCEPTIONS; undocumented drift fails.
Run: floci-pyenv/bin/python -m pytest tests/gcp -q
"""
import collections
import json
import os
import unittest

STATE_ROOT = os.environ.get("STATE_ROOT", ".state/dev/gcp")

PLANNED = {
    "bootstrap": {"google_compute_network": 1, "google_compute_subnetwork": 2,
                  "google_compute_firewall": 3, "google_kms_key_ring": 1,
                  "google_kms_crypto_key": 1, "google_artifact_registry_repository": 5,
                  "google_storage_bucket": 1, "google_project_service": 8},
    "iam": {"google_service_account": 3, "google_project_iam_member": 5},
    "stateful": {"google_sql_database_instance": 1, "google_sql_database": 1,
                 "google_sql_user": 1, "google_firestore_database": 1,
                 "google_pubsub_topic": 2, "google_pubsub_subscription": 2,
                 "google_secret_manager_secret": 3,
                 "google_secret_manager_secret_version": 2},
    "standard": {"google_container_cluster": 1, "google_container_node_pool": 1,
                "google_cloud_run_v2_service": 1, "helm_release": 2,
                "kubernetes_namespace": 2, "null_resource": 2},
}

# (stack, type) -> (planned, observed, reason)
EXCEPTIONS = {
    ("bootstrap", "google_artifact_registry_repository"):
        (5, 0, "emulator 404, placeholder outputs only; Block 0 verdict"),
    ("iam", "google_project_iam_member"):
        (5, 4, "config defines 4 bindings; table provisional"),
    ("stateful", "google_firestore_database"):
        (1, 0, "gRPC-only, SDK path; not provisionable via provider"),
    ("stateful", "google_secret_manager_secret"):
        (3, 2, "argocd-admin plus app-credentials only; third TBD"),
    ("standard", "kubernetes_namespace"):
        (2, 1, "argocd only; smartcloud ns via overlay, not terraform"),
    ("standard", "null_resource"):
        (2, 1, "single admin-password hook; second init deferred"),
}


def observed(stack):
    path = os.path.join(STATE_ROOT, stack, "terraform.tfstate")
    with open(path) as f:
        data = json.load(f)
    counts = collections.Counter()
    for r in data.get("resources", []):
        counts[r.get("type", "?")] += len(r.get("instances", []))
    return counts


class TestReconcile(unittest.TestCase):
    def test_planned_matches_observed(self):
        for stack, planned in PLANNED.items():
            with self.subTest(stack=stack):
                obs = observed(stack)
                for rtype, want in planned.items():
                    got = obs.get(rtype, 0)
                    if got == want:
                        continue
                    key = (stack, rtype)
                    self.assertIn(key, EXCEPTIONS,
                                  f"undocumented drift {stack}/{rtype}: planned={want} observed={got}")
                    exp_planned, exp_obs, _reason = EXCEPTIONS[key]
                    self.assertEqual((want, got), (exp_planned, exp_obs),
                                     f"deviation changed {stack}/{rtype}")


if __name__ == "__main__":
    unittest.main()
