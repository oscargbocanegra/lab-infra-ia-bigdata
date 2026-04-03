#!/bin/bash
set -e

echo "==> Iniciando configuración de Jupyter..."

# ── Leer credenciales MinIO desde Docker Secrets ─────────────
# AWS_ACCESS_KEY_ID_FILE / AWS_SECRET_ACCESS_KEY_FILE NO son variables
# estándar reconocidas por boto3, s3fs ni PySpark.
# Leemos los secrets y los exportamos como las vars estándar que SÍ leen.
if [ -f /run/secrets/minio_access_key ]; then
    export AWS_ACCESS_KEY_ID
    AWS_ACCESS_KEY_ID=$(cat /run/secrets/minio_access_key)
fi

if [ -f /run/secrets/minio_secret_key ]; then
    export AWS_SECRET_ACCESS_KEY
    AWS_SECRET_ACCESS_KEY=$(cat /run/secrets/minio_secret_key)
fi

# Endpoint MinIO para boto3/s3fs (s3:// sin prefijo s3a)
export AWS_ENDPOINT_URL=http://minio:9000

# ── Configurar jupyter-ai con Ollama como provider ───────────
# jupyter-ai usa jupyter_ai_config.json para el modelo por defecto.
# Ollama corre en la red internal (sin auth) → http://ollama:11434
# Modelo: qwen2.5-coder:7b — especializado en código, ~5.5 GB VRAM
#
# IMPORTANTE: usamos jupyter_lab_config.py (no jupyter_server_config.py)
# porque Jupyter regenera jupyter_server_config.py al arrancar, pisando
# cualquier configuración que pongamos ahí. jupyter_lab_config.py es
# cargado por el servidor pero NUNCA regenerado automáticamente.
# ─────────────────────────────────────────────────────────────
JUPYTER_CONFIG_DIR="/home/jovyan/.jupyter"
mkdir -p "$JUPYTER_CONFIG_DIR"

# jupyter_lab_config.py — Jupyter lo carga pero nunca lo regenera
# Siempre lo escribimos para garantizar que la config de Ollama esté activa
cat > "$JUPYTER_CONFIG_DIR/jupyter_lab_config.py" << 'EOF'
# ── jupyter-ai: Ollama provider (LAN, sin cloud) ──────────────
# Modelo default: qwen2.5-coder:7b
# Endpoint: http://ollama:11434 (red internal de Docker Swarm)
c.AiExtension.default_language_model = "ollama:qwen2.5-coder:7b"
c.AiExtension.allowed_providers = ["ollama"]

# ── jupyter-lsp: Language Server Protocol ─────────────────────
# jedi-language-server: autocompletado clásico con tipos y docstrings
c.LanguageServerManager.autodetect = True
EOF
echo "==> [jupyter-ai] jupyter_lab_config.py escrito ✓"

# jupyter_ai_config.json — config persistente del chat panel
# Solo se crea si no existe para respetar cambios del usuario
AI_CONFIG="$JUPYTER_CONFIG_DIR/jupyter_ai_config.json"
if [ ! -f "$AI_CONFIG" ]; then
    cat > "$AI_CONFIG" << 'EOF'
{
  "model_provider_id": "ollama:qwen2.5-coder:7b",
  "fields": {
    "base_url": "http://ollama:11434"
  }
}
EOF
    echo "==> [jupyter-ai] jupyter_ai_config.json creado ✓"
fi

echo "==> Ejecutando init de kernels..."

# Ejecutar script de inicialización de kernels
if [ -f /tmp/init-kernels.sh ]; then
    bash /tmp/init-kernels.sh
fi

echo "==> Iniciando Jupyter Lab..."

# Ejecutar el comando original de Jupyter
exec start-notebook.sh "$@"

