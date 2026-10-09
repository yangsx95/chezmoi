import json
import os
import re
import secrets
import sqlite3
import subprocess
import sys
import time
import tomllib
import urllib.error
import urllib.request
from pathlib import Path


config_dir = Path(__file__).resolve().parent
data_dir = Path.home() / ".local/share/litellm"
env_file = data_dir / ".env"
required_keys = {"DEEPSEEK_API_KEY", "COMPANY_API_KEY", "COMPANY_API_BASE"}
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
    print(f"Created {env_file}; add provider credentials or configure CC Switch")


def provider_environment():
    configured = set(os.environ)
    for line in env_file.read_text().splitlines():
        key, separator, value = line.partition("=")
        if separator and value.strip():
            configured.add(key.strip())
    missing = required_keys - configured
    if not missing:
        return {}

    db_path = Path.home() / ".cc-switch/cc-switch.db"
    if not db_path.exists():
        raise SystemExit(f"Add {', '.join(sorted(missing))} to {env_file}")
    with sqlite3.connect(f"file:{db_path}?mode=ro", uri=True) as db:
        providers = {
            name: json.loads(settings)
            for name, settings in db.execute(
                "SELECT name, settings_config FROM providers WHERE app_type = ?",
                ("codex",),
            )
        }
    try:
        company = providers["公司专用"]
        candidates = {
            "DEEPSEEK_API_KEY": providers["DeepSeek"]["auth"]["OPENAI_API_KEY"],
            "COMPANY_API_KEY": company["auth"]["OPENAI_API_KEY"],
            "COMPANY_API_BASE": tomllib.loads(company["config"])["model_providers"]["custom"]["base_url"],
        }
    except KeyError as error:
        raise SystemExit(f"CC Switch is missing {error}; add credentials to {env_file}") from error
    if any(not candidates[key] for key in missing):
        raise SystemExit(f"Add {', '.join(sorted(missing))} to {env_file}")
    return {key: candidates[key] for key in missing}


def compose_command(arguments):
    return [
        "docker", "compose", "--project-directory", str(config_dir),
        "--env-file", str(env_file), "-f", str(config_dir / "compose.yaml"),
        *arguments,
    ]


def request_json(url, token, payload=None):
    headers = {"Authorization": f"Bearer {token}"}
    if payload is not None:
        headers["Content-Type"] = "application/json"
    request = urllib.request.Request(
        url,
        data=json.dumps(payload).encode() if payload is not None else None,
        headers=headers,
    )
    try:
        with urllib.request.urlopen(request, timeout=15) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        raise RuntimeError(f"Model API returned HTTP {error.code}: {url}") from error


def company_model_id(model_id):
    return (
        isinstance(model_id, str)
        and re.fullmatch(r"[A-Za-z0-9._-]+", model_id) is not None
        and model_id != "codex-auto-review"
        and not model_id.startswith("gpt-image-")
    )


def sync_company_models(environment, prune=False):
    compose_config = subprocess.run(
        compose_command(["config", "--format", "json"]),
        env=environment, check=True, capture_output=True, text=True,
    )
    credentials = json.loads(compose_config.stdout)["services"]["proxy"]["environment"]
    company_url = credentials["COMPANY_API_BASE"].rstrip("/") + "/models"
    upstream = request_json(company_url, credentials["COMPANY_API_KEY"])
    models = upstream.get("data")
    if not isinstance(models, list):
        raise RuntimeError("Company model endpoint did not return a model list")
    model_ids = sorted({item.get("id") for item in models if company_model_id(item.get("id"))})
    if not model_ids:
        raise RuntimeError("Company model list is empty; existing models were kept")

    master_key = credentials["LITELLM_MASTER_KEY"]
    deployments = request_json(proxy_url + "/model/info", master_key)["data"]
    names = {deployment["model_name"] for deployment in deployments}
    managed = {
        deployment["model_info"]["id"]: deployment
        for deployment in deployments
        if deployment["model_info"].get("db_model")
        and deployment["model_info"]["id"].startswith("company-sync-")
        and deployment["model_name"].startswith("company-")
    }
    desired = {f"company-sync-{model_id}" for model_id in model_ids}
    added = 0
    for model_id in model_ids:
        name = f"company-{model_id}"
        deployment_id = f"company-sync-{model_id}"
        if deployment_id in managed or name in names:
            continue
        request_json(
            proxy_url + "/model/new", master_key,
            {
                "model_name": name,
                "litellm_params": {
                    "model": f"openai/{model_id}",
                    "api_base": "os.environ/COMPANY_API_BASE",
                    "api_key": "os.environ/COMPANY_API_KEY",
                },
                "model_info": {"id": deployment_id},
            },
        )
        added += 1

    stale = sorted(managed.keys() - desired)
    if prune:
        for deployment_id in stale:
            request_json(proxy_url + "/model/delete", master_key, {"id": deployment_id})
    print(f"Company models: {len(model_ids)} available, {added} added, {len(stale)} stale")
    if stale and not prune:
        print("Run sync-company-models --prune to remove stale synchronized models")


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
    if arguments == ["init"]:
        initialize()
    else:
        if not env_file.is_file():
            raise SystemExit(f"Run python3 {config_dir / 'start.py'} init first")
        environment = os.environ.copy()
        environment.update(provider_environment())
        if arguments in (["sync-company-models"], ["sync-company-models", "--prune"]):
            sync_company_models(environment, prune="--prune" in arguments)
        else:
            subprocess.run(
                compose_command(arguments or ["up", "-d"]),
                env=environment, check=True,
            )
            if not arguments or arguments == ["up", "-d"]:
                wait_for_proxy()
                try:
                    sync_company_models(environment)
                except (OSError, KeyError, ValueError, RuntimeError) as error:
                    print(f"Model sync failed; proxy remains running: {error}", file=sys.stderr)
