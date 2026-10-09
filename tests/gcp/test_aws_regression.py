"""AWS regression test (QA-7). Existing AWS verify must still pass.

Skips when the AWS emulator is down; GCP QA never starts it.
Run: floci-pyenv/bin/python -m pytest tests/gcp -q
"""
import os
import subprocess
import unittest
import urllib.request

REPO_ROOT = os.environ.get("REPO_ROOT", ".")
AWS_HEALTH = os.environ.get("AWS_HEALTH", "http://localhost:4566/_localstack/health")


def aws_up():
    try:
        with urllib.request.urlopen(AWS_HEALTH, timeout=5) as r:
            return r.status == 200
    except Exception:
        return False


@unittest.skipUnless(aws_up(), "AWS emulator down")
class TestAWSRegression(unittest.TestCase):
    def test_aws_verify(self):
        script = os.path.join(REPO_ROOT, "verify.sh")
        self.assertTrue(os.path.exists(script), f"missing {script}")
        p = subprocess.run(["bash", script], capture_output=True, text=True,
                           timeout=600, cwd=REPO_ROOT)
        self.assertEqual(p.returncode, 0,
                         f"verify.sh failed:\n{p.stdout[-2000:]}\n{p.stderr[-2000:]}")


if __name__ == "__main__":
    unittest.main()
