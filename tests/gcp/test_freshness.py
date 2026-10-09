"""Freshness tests (QA-7). State must be newer than any pending plan.

An unapplied .tfplan newer than its stack state means the live emulator
lags the reviewed intent. Plan files hold secrets and must never commit.
Run: floci-pyenv/bin/python -m pytest tests/gcp -q
"""
import glob
import os
import unittest

REPO_ROOT = os.environ.get("REPO_ROOT", ".")
STATE_ROOT = os.environ.get("STATE_ROOT", ".state/dev/gcp")
STACKS = ("bootstrap", "iam", "stateful", "standard")


class TestFreshness(unittest.TestCase):
    def test_no_stale_pending_plans(self):
        for stack in STACKS:
            with self.subTest(stack=stack):
                state = os.path.join(STATE_ROOT, stack, "terraform.tfstate")
                self.assertTrue(os.path.exists(state), f"missing {state}")
                state_mtime = os.path.getmtime(state)
                plans = glob.glob(os.path.join(REPO_ROOT, "terragrunt", "gcp",
                                               stack, "*.tfplan"))
                plans += glob.glob(os.path.join(REPO_ROOT, "terragrunt", "gcp",
                                                stack, ".tfplan", "*.tfplan"))
                stale = [p for p in plans if os.path.getmtime(p) > state_mtime]
                self.assertEqual(stale, [], f"unapplied plans newer than state: {stale}")

    def test_state_nonempty(self):
        for stack in STACKS:
            with self.subTest(stack=stack):
                state = os.path.join(STATE_ROOT, stack, "terraform.tfstate")
                self.assertGreater(os.path.getsize(state), 0, f"empty {state}")


if __name__ == "__main__":
    unittest.main()
