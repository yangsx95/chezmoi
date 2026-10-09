import runpy
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "dot_config/private_litellm/start.py"


class LiteLLMBootstrapTest(unittest.TestCase):
    def test_start_creates_secrets_once(self):
        with tempfile.TemporaryDirectory() as temporary_home:
            script = runpy.run_path(str(SCRIPT))
            env_file = Path(temporary_home) / ".local/share/litellm/.env"
            script["initialize"].__globals__["data_dir"] = env_file.parent
            script["initialize"].__globals__["env_file"] = env_file
            script["initialize"]()
            original = env_file.read_bytes()

            script["initialize"]()
            self.assertEqual(original, env_file.read_bytes())
            self.assertEqual(stat.S_IMODE(env_file.stat().st_mode), 0o600)
            for key in ("LITELLM_MASTER_KEY", "LITELLM_SALT_KEY", "POSTGRES_PASSWORD"):
                self.assertIn(f"{key}=".encode(), original)

            result = subprocess.run(["python3", str(SCRIPT), "init"], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Usage:", result.stderr)


if __name__ == "__main__":
    unittest.main()
