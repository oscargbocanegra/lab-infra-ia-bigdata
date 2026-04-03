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
# JARVIS_MODEL viene como variable de entorno desde stack.yml.
# Desde Portainer: Services → jupyter_jupyter_ogiovanni/odavid
#                  → Environment → JARVIS_MODEL → cambiar valor → Update
# Fallback: qwen2.5-coder:7b si la variable no está seteada
JARVIS_MODEL="${JARVIS_MODEL:-ollama:qwen2.5-coder:7b}"
JUPYTER_CONFIG_DIR="/home/jovyan/.jupyter"
mkdir -p "$JUPYTER_CONFIG_DIR"

# jupyter_lab_config.py — Jupyter lo carga pero nunca lo regenera
# Siempre lo escribimos para garantizar que la config de Ollama esté activa
cat > "$JUPYTER_CONFIG_DIR/jupyter_lab_config.py" << EOF
# ── jupyter-ai: Ollama provider (LAN, sin cloud) ──────────────
# Modelo activo: ${JARVIS_MODEL}
# Endpoint: http://ollama:11434 (red internal de Docker Swarm)
# NOTA: initial_language_model es el traitlet correcto en jupyter-ai 2.x
c.AiExtension.initial_language_model = "${JARVIS_MODEL}"
c.AiExtension.allowed_providers = ["ollama"]

# ── jupyter-lsp: Language Server Protocol ─────────────────────
c.LanguageServerManager.autodetect = True
EOF
echo "==> [jupyter-ai] jupyter_lab_config.py escrito (modelo: ${JARVIS_MODEL}) ✓"

# jupyter_jupyter_ai_config.json — config persistente del chat panel
# Nombre correcto según la doc oficial de jupyter-ai 2.x
# Solo se crea si no existe para respetar cambios del usuario
AI_CONFIG="$JUPYTER_CONFIG_DIR/jupyter_jupyter_ai_config.json"
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

# ── JupyterLab settings: autocompletado continuo (as-you-type) ─
# jupyterlab-lsp por default requiere Tab para mostrar completions.
# Con continuousHinting: true se activa el modo automático (Hinterland mode).
# El archivo va en el Settings directory de JupyterLab (persistido en NVMe).
LAB_SETTINGS_DIR="/home/jovyan/.jupyter/lab/user-settings"
mkdir -p "$LAB_SETTINGS_DIR/@jupyter-lsp/jupyterlab-lsp"

LSP_COMPLETION_SETTINGS="$LAB_SETTINGS_DIR/@jupyter-lsp/jupyterlab-lsp/completion.jupyterlab-settings"
if [ ! -f "$LSP_COMPLETION_SETTINGS" ]; then
    cat > "$LSP_COMPLETION_SETTINGS" << 'EOF'
{
  "continuousHinting": true,
  "suppressContinuousHintingIn": ["Comment", "BlockComment", "LineComment", "String"],
  "theme": "vscode",
  "layout": "side-by-side",
  "waitForBusyKernel": true
}
EOF
    echo "==> [lsp] Autocompletado continuo configurado ✓"
fi


# ── IPython startup: auto-cargar jupyter_ai_magics en todos los kernels ──
# Los archivos en ~/.ipython/profile_default/startup/ se ejecutan
# automáticamente al iniciar cualquier kernel IPython (python3, llm, ia, bigdata).
# Esto evita tener que correr %load_ext jupyter_ai_magics manualmente.
IPYTHON_STARTUP="/home/jovyan/.ipython/profile_default/startup"
mkdir -p "$IPYTHON_STARTUP"

MAGIC_STARTUP="$IPYTHON_STARTUP/00-jupyter-ai-magics.py"
# Siempre sobreescribir — el modelo viene de $JARVIS_MODEL (env var), se actualiza en cada arranque
cat > "$MAGIC_STARTUP" << EOF
# ── Jarvis: magic personalizado para jupyter-ai ───────────────────────────────
# Modelo activo: ${JARVIS_MODEL}
# Para cambiar el modelo: Portainer → Service → Environment → JARVIS_MODEL
#
# Uso en cualquier notebook:
#   %%JARVIS
#   crea una función que calcule fibonacci
# ─────────────────────────────────────────────────────────────────────────────
JARVIS_MODEL = "${JARVIS_MODEL}"

try:
    _ip = get_ipython()
    _ip.run_line_magic('load_ext', 'jupyter_ai_magics')

    from IPython.display import display

    def JARVIS(line, cell):
        """Magic %%JARVIS / %%jarvis — envía el prompt al modelo configurado en JARVIS_MODEL."""
        result = _ip.run_cell_magic('ai', JARVIS_MODEL, cell)
        if result is not None:
            display(result)

    # Registrar ambas variantes — IPython es case-sensitive
    _ip.register_magic_function(JARVIS, magic_kind='cell', magic_name='JARVIS')
    _ip.register_magic_function(JARVIS, magic_kind='cell', magic_name='jarvis')

except Exception:
    pass  # Silencioso si jupyter_ai_magics no está disponible en este kernel
EOF
echo "==> [ipython] Magic %%JARVIS configurado (modelo: ${JARVIS_MODEL}) ✓"

echo "==> Iniciando Jupyter Lab..."

# Ejecutar el comando original de Jupyter
exec start-notebook.sh "$@"

