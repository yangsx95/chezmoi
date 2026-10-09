import json
import os
import secrets
import subprocess
import sys
import time
import urllib.request
from pathlib import Path


config_dir = Path(__file__).resolve().parent
data_dir = Path.home() / ".local/share/litellm"
env_file = data_dir / ".env"
proxy_url = "http://127.0.0.1:4000"


def initialize():
    data_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
    if env_file.exists():
        print(f"Using existing {env_file}")
        return
    descriptor = os.open(env_file, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "w") as output:
        output.write(f"LITELLM_MASTER_KEY=sk-{secrets.token_hex(32)}\n")
        output.write(f"LITELLM_SALT_KEY=sk-{secrets.token_hex(32)}\n")
        output.write(f"POSTGRES_PASSWORD={secrets.token_hex(32)}\n")
    print(f"Created {env_file}")


def compose_command(arguments):
    return [
        "docker", "compose", "--project-directory", str(config_dir),
        "--env-file", str(env_file), "-f", str(config_dir / "compose.yaml"),
        *arguments,
    ]


def wait_for_proxy():
    for _ in range(45):
        try:
            with urllib.request.urlopen(proxy_url + "/health/readiness", timeout=2) as response:
                if json.load(response).get("status") == "healthy":
                    return
        except (OSError, ValueError):
            pass
        time.sleep(2)
    raise RuntimeError("LiteLLM did not become ready within 90 seconds")


if __name__ == "__main__":
    arguments = sys.argv[1:]
    if arguments == ["start"] or arguments == ["restart"]:
        initialize()
        compose_args = ["up", "-d"]
        if arguments == ["restart"]:
            compose_args.extend(["--force-recreate", "proxy"])
        subprocess.run(compose_command(compose_args), check=True)
        wait_for_proxy()
    elif arguments and arguments[0] in {"stop", "ps", "logs", "exec"}:
        if not env_file.is_file():
            raise SystemExit("Run litellm-local start first")
        subprocess.run(compose_command(arguments), check=True)
    else:
        raise SystemExit("Usage: litellm-local {start|restart|stop|ps|logs [service]|exec ...}")
