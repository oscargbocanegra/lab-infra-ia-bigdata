#!/bin/bash
# ============================================================
# init-kernels.sh — Inicialización de kernels Jupyter
# ============================================================
# Kernels creados:
#   llm      → PyTorch + Transformers + LangChain + Ollama client
#   ia       → Scikit-learn + TF/Keras + XGBoost + OpenCV
#   bigdata  → PySpark + Delta Lake + MinIO (s3a) + Pandas + Dask
#
# Extensiones de servidor (instaladas en el Python base del container):
#   jupyter-lsp              → protocolo LSP para intellisense clásico
#   jedi-language-server     → backend LSP para Python (tipos, docs, go-to-def)
#   jupyter-ai               → chat IA + %%ai magic via Ollama (LAN, sin cloud)
#   langchain-community      → provider Ollama para jupyter-ai
#
# Los venvs se persisten en /home/jovyan/.venv (montado en NVMe)
# Solo se instalan si el kernel NO existe ya → idempotente
# ============================================================
set -e

KERNEL_DIR="/home/jovyan/.local/share/jupyter/kernels"
VENV_BASE="/home/jovyan/.venv"

kernel_exists() {
    [ -d "$KERNEL_DIR/$1" ]
}

# ── Extensiones de servidor (Python base del container) ──────
# Se instalan una sola vez en el entorno base de JupyterLab.
# jupyter-lsp + jedi: intellisense clásico (tipos, docstrings, go-to-def)
# jupyter-ai + langchain-community: chat IA y %%ai magic vía Ollama (LAN)
# ─────────────────────────────────────────────────────────────
SERVER_EXT_FLAG="/home/jovyan/.local/.server-extensions-installed"

if [ ! -f "$SERVER_EXT_FLAG" ]; then
    echo "==> [server-ext] Instalando extensiones de servidor JupyterLab..."

    pip install --no-cache-dir --quiet \
        "jupyter-lsp>=2.2.0" \
        "jedi-language-server>=0.41.0" \
        "jupyter-ai>=2.20.0" \
        "langchain-community>=0.3.0" \
        "langchain-ollama>=0.2.0"

    # Habilitar las extensiones en el servidor
    jupyter server extension enable --user jupyter_lsp
    jupyter server extension enable --user jupyter_ai

    touch "$SERVER_EXT_FLAG"
    echo "==> [server-ext] Extensiones instaladas y habilitadas ✓"
else
    echo "==> [server-ext] Ya instaladas, saltando."
fi

# ── Kernel: LLM ──────────────────────────────────────────────
if ! kernel_exists "llm"; then
    echo "==> [kernel:llm] Creando entorno..."
    python -m venv "$VENV_BASE/llm"
    source "$VENV_BASE/llm/bin/activate"

    pip install --upgrade pip setuptools wheel --quiet

    # PyTorch con CUDA 12.1 (compatible con driver 535 / CUDA 12.2)
    pip install --no-cache-dir \
        torch torchvision torchaudio \
        --index-url https://download.pytorch.org/whl/cu121 --quiet

    pip install --no-cache-dir \
        ipykernel \
        transformers \
        accelerate \
        bitsandbytes \
        sentencepiece \
        protobuf \
        datasets \
        peft \
        trl \
        langchain \
        langchain-community \
        langchain-ollama \
        openai \
        tiktoken \
        ollama \
        huggingface_hub \
        jedi \
        --quiet

    python -m ipykernel install --user --name=llm --display-name="Python (LLM - PyTorch + LangChain)"
    deactivate
    echo "==> [kernel:llm] Listo ✓"
else
    echo "==> [kernel:llm] Ya existe, saltando."
fi

# ── Kernel: IA ───────────────────────────────────────────────
if ! kernel_exists "ia"; then
    echo "==> [kernel:ia] Creando entorno..."
    python -m venv "$VENV_BASE/ia"
    source "$VENV_BASE/ia/bin/activate"

    pip install --upgrade pip setuptools wheel --quiet

    pip install --no-cache-dir \
        torch torchvision torchaudio \
        --index-url https://download.pytorch.org/whl/cu121 --quiet

    pip install --no-cache-dir \
        ipykernel \
        numpy \
        pandas \
        matplotlib \
        seaborn \
        plotly \
        scikit-learn \
        scipy \
        xgboost \
        lightgbm \
        catboost \
        tensorflow \
        keras \
        opencv-python-headless \
        pillow \
        mlflow \
        optuna \
        jedi \
        --quiet

    python -m ipykernel install --user --name=ia --display-name="Python (IA - Scikit + TF + XGBoost)"
    deactivate
    echo "==> [kernel:ia] Listo ✓"
else
    echo "==> [kernel:ia] Ya existe, saltando."
fi

# ── Kernel: BigData ──────────────────────────────────────────
if ! kernel_exists "bigdata"; then
    echo "==> [kernel:bigdata] Creando entorno..."
    python -m venv "$VENV_BASE/bigdata"
    source "$VENV_BASE/bigdata/bin/activate"

    pip install --upgrade pip setuptools wheel --quiet

    # PySpark 3.5.x — compatible con la imagen bitnami/spark:3.5
    pip install --no-cache-dir \
        ipykernel \
        pyspark==3.5.3 \
        delta-spark==3.2.1 \
        pandas \
        pyarrow \
        numpy \
        matplotlib \
        seaborn \
        plotly \
        dask[complete] \
        "boto3>=1.34" \
        "s3fs>=2024.2" \
        findspark \
        jedi \
        --quiet

    python -m ipykernel install --user --name=bigdata --display-name="Python (BigData - PySpark + Delta + MinIO)"
    deactivate
    echo "==> [kernel:bigdata] Listo ✓"
else
    echo "==> [kernel:bigdata] Ya existe, saltando."
fi

echo ""
echo "==> Kernels disponibles:"
jupyter kernelspec list
echo "==> Inicialización completada ✓"
