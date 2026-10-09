import io
import json
import os
import runpy
import stat
import subprocess
import tempfile
import types
import unittest
from contextlib import redirect_stdout
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "dot_config/private_litellm/start.py"


class LiteLLMBootstrapTest(unittest.TestCase):
    def test_company_model_filter(self):
        accepts = runpy.run_path(str(SCRIPT))["company_model_id"]
        self.assertTrue(accepts("gpt-6-sol"))
        self.assertTrue(accepts("deepseek-v4-pro"))
        self.assertFalse(accepts("gpt-image-2.5-flare"))
        self.assertFalse(accepts("codex-auto-review"))
        self.assertFalse(accepts("../invalid"))

    def test_sync_adds_models_without_deleting_stale_entries(self):
        sync = runpy.run_path(str(SCRIPT))["sync_company_models"]
        calls = []

        def request_json(url, token, payload=None):
            calls.append((url, payload))
            if url.endswith("/models"):
                return {"data": [{"id": "gpt-6-sol"}, {"id": "gpt-6-luna"}, {"id": "gpt-image-2.5-flare"}]}
            if url.endswith("/model/info"):
                return {"data": [
                    {"model_name": "company-gpt-6-sol", "model_info": {"id": "static", "db_model": False}},
                    {"model_name": "company-old", "model_info": {"id": "company-sync-old", "db_model": True}},
                ]}
            return {}

        sync.__globals__["request_json"] = request_json
        sync.__globals__["subprocess"] = types.SimpleNamespace(
            run=lambda *args, **kwargs: types.SimpleNamespace(stdout=json.dumps({"services": {"proxy": {
                "environment": {
                    "COMPANY_API_BASE": "https://company.example/v1",
                    "COMPANY_API_KEY": "test-key",
                    "LITELLM_MASTER_KEY": "test-master",
                }
            }}}))
        )
        with redirect_stdout(io.StringIO()):
            sync({})

        additions = [payload for url, payload in calls if url.endswith("/model/new")]
        self.assertEqual([item["model_name"] for item in additions], ["company-gpt-6-luna"])
        self.assertEqual(additions[0]["model_info"]["id"], "company-sync-gpt-6-luna")
        self.assertFalse(any(url.endswith("/model/delete") for url, _ in calls))

    def test_start_creates_secrets_once_and_requires_provider_credentials(self):
        with tempfile.TemporaryDirectory() as temporary_home:
            environment = {key: value for key, value in os.environ.items() if key not in {
                "DEEPSEEK_API_KEY", "COMPANY_API_KEY", "COMPANY_API_BASE"
            }}
            environment["HOME"] = temporary_home
            first = subprocess.run(
                ["python3", str(SCRIPT), "start"], env=environment, capture_output=True, text=True
            )
            self.assertNotEqual(first.returncode, 0)
            self.assertIn("DEEPSEEK_API_KEY", first.stderr)
            env_file = Path(temporary_home) / ".local/share/litellm/.env"
            original = env_file.read_bytes()

            subprocess.run(["python3", str(SCRIPT), "start"], env=environment, capture_output=True)
            self.assertEqual(original, env_file.read_bytes())
            self.assertEqual(stat.S_IMODE(env_file.stat().st_mode), 0o600)
            for key in ("LITELLM_MASTER_KEY", "LITELLM_SALT_KEY", "POSTGRES_PASSWORD"):
                self.assertIn(f"{key}=".encode(), original)

            result = subprocess.run(["python3", str(SCRIPT), "init"], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Usage:", result.stderr)


if __name__ == "__main__":
    unittest.main()
