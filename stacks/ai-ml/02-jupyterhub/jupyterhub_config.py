"""Configuración de JupyterHub para Docker Swarm."""

import os
from urllib.parse import quote_plus

from dockerspawner import SwarmSpawner
from nativeauthenticator import NativeAuthenticator


def required_env(name: str) -> str:
    """Retorna una variable obligatoria o detiene el arranque."""
    value = os.environ.get(name, "").strip()
    if not value:
        raise RuntimeError(f"Variable obligatoria no definida: {name}")
    return value


def env(name: str, default: str) -> str:
    """Retorna una variable opcional con valor predeterminado."""
    return os.environ.get(name, default).strip()


c = get_config()  # noqa: F821

# ------------------------------------------------------------------
# JupyterHub
# ------------------------------------------------------------------
c.JupyterHub.bind_url = "http://0.0.0.0:8000"
c.JupyterHub.hub_bind_url = "http://0.0.0.0:8081"
c.JupyterHub.hub_connect_url = env(
    "JUPYTERHUB_HUB_CONNECT_URL",
    "http://jupyterhub_jupyterhub:8081",
)
c.JupyterHub.cookie_secret_file = required_env(
    "JUPYTERHUB_COOKIE_SECRET_FILE"
)
c.JupyterHub.cleanup_servers = False
c.JupyterHub.shutdown_on_logout = False

# ------------------------------------------------------------------
# PostgreSQL
# ------------------------------------------------------------------
db_host = env("JUPYTERHUB_DB_HOST", "postgres")
db_port = env("JUPYTERHUB_DB_PORT", "5432")
db_name = env("JUPYTERHUB_DB_NAME", "jupyterhub")
db_user = env("JUPYTERHUB_DB_USER", "jupyterhub")
db_password = required_env("JUPYTERHUB_DB_PASSWORD")

c.JupyterHub.db_url = (
    "postgresql+psycopg://"
    f"{quote_plus(db_user)}:{quote_plus(db_password)}"
    f"@{db_host}:{db_port}/{db_name}"
)

# ------------------------------------------------------------------
# Autenticación
# ------------------------------------------------------------------
c.JupyterHub.authenticator_class = NativeAuthenticator
c.Authenticator.admin_users = {"ogiovanni"}
c.NativeAuthenticator.open_signup = False
c.NativeAuthenticator.minimum_password_length = 12
c.NativeAuthenticator.check_common_password = True
c.NativeAuthenticator.allowed_failed_logins = 5
c.NativeAuthenticator.seconds_before_next_try = 120

# ------------------------------------------------------------------
# SwarmSpawner
# ------------------------------------------------------------------
c.JupyterHub.spawner_class = SwarmSpawner

c.SwarmSpawner.image = env(
    "JUPYTERHUB_SINGLEUSER_IMAGE",
    "giovannotti/lab-jupyter:sha-0cbf11c",
)
c.SwarmSpawner.cmd = ["jupyterhub-singleuser"]
c.SwarmSpawner.name_template = "jupyterhub-user-{username}"
c.SwarmSpawner.network_name = env(
    "JUPYTERHUB_NETWORK_NAME",
    "internal",
)
c.SwarmSpawner.use_internal_ip = True
c.SwarmSpawner.remove_containers = True
c.SwarmSpawner.pull_policy = "ifnotpresent"

c.SwarmSpawner.notebook_dir = "/home/jovyan/work"
c.SwarmSpawner.default_url = "/lab"

c.SwarmSpawner.extra_placement_spec = {
    "constraints": [
        "node.hostname==master2",
        "node.labels.tier==compute",
    ]
}

# Reservas bajas mientras conviven los Jupyter standalone.
c.SwarmSpawner.cpu_guarantee = 0.25
c.SwarmSpawner.cpu_limit = 4.0
c.SwarmSpawner.mem_guarantee = "512M"
c.SwarmSpawner.mem_limit = "8G"

c.SwarmSpawner.volumes = {
    "/srv/fastdata/jupyterhub/users/{username}/work": {
        "bind": "/home/jovyan/work",
        "mode": "rw",
    },
    "/srv/fastdata/jupyterhub/users/{username}/.local": {
        "bind": "/home/jovyan/.local",
        "mode": "rw",
    },
    "/srv/fastdata/jupyterhub/users/{username}/.venv": {
        "bind": "/home/jovyan/.venv",
        "mode": "rw",
    },
    "/srv/fastdata/jupyterhub/users/{username}/.cache": {
        "bind": "/home/jovyan/.cache",
        "mode": "rw",
    },
    "/srv/datalake": {
        "bind": "/home/jovyan/datalake",
        "mode": "ro",
    },
    "/srv/datalake/datasets": {
        "bind": "/home/jovyan/datasets",
        "mode": "ro",
    },
    "/srv/datalake/notebooks": {
        "bind": "/home/jovyan/shared-notebooks",
        "mode": "rw",
    },
    "/srv/datalake/artifacts": {
        "bind": "/home/jovyan/artifacts",
        "mode": "rw",
    },
}

c.SwarmSpawner.environment = {
    "JUPYTER_ENABLE_LAB": "yes",
    "OLLAMA_HOST": "http://ollama:11434",
    "SPARK_MASTER_URL": "spark://spark_master:7077",
    "JARVIS_MODEL": "ollama:qwen2.5-coder:14b",
    "NVIDIA_VISIBLE_DEVICES": "0",
    "NVIDIA_DRIVER_CAPABILITIES": "compute,utility",
    "CUDA_VISIBLE_DEVICES": "0",
    "PYTHONNOUSERSITE": "1",
}

# Tiempo adicional para crear y converger el servicio Swarm.
c.Spawner.start_timeout = 180
c.Spawner.http_timeout = 120

# Evita que un usuario modifique la configuración global del servidor.
c.Spawner.disable_user_config = True

# Logging operativo, sin activar trazas sensibles.
c.JupyterHub.log_level = env("JUPYTERHUB_LOG_LEVEL", "INFO")
