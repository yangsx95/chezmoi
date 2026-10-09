import os
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "dot_config/private_litellm/start.py"


class LiteLLMBootstrapTest(unittest.TestCase):
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
