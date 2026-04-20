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
# Las extensiones de servidor se reinstalan en CADA arranque (opt/conda es efímero)
# ============================================================
set -e

KERNEL_DIR="/home/jovyan/.local/share/jupyter/kernels"
VENV_BASE="/home/jovyan/.venv"

kernel_exists() {
    [ -d "$KERNEL_DIR/$1" ]
}

# ── Extensiones de servidor (Python base del container) ──────
# Se instalan en CADA arranque del container porque /opt/conda es
# efímero (capa del container, no persistida en NVMe).
# jupyter-lsp + jupyterlab-lsp + jedi: intellisense clásico
# jupyter-ai + langchain: chat IA y %%ai magic vía Ollama (LAN)
#
# La imagen base trae JupyterLab 4.0.7. jupyter-ai 2.x requiere >=4.2.
# Actualizamos jupyterlab a 4.2.x antes de instalar las extensiones.
# ─────────────────────────────────────────────────────────────
echo "==> [server-ext] Actualizando JupyterLab a 4.2.x..."
pip install --no-cache-dir --quiet \
    "jupyterlab>=4.2.0,<4.3.0" \
    "jupyterlab-server>=2.27.0"

echo "==> [server-ext] Instalando extensiones jupyter-lsp y jupyter-ai..."
pip install --no-cache-dir --quiet \
    "jupyter-lsp>=2.2.0,<3.0" \
    "jupyterlab-lsp>=5.0.0,<6.0" \
    "jedi-language-server>=0.41.0" \
    "jupyter-ai>=2.20.0,<3.0" \
    "langchain-community>=0.3.0,<0.4.0" \
    "langchain-ollama>=0.2.0,<1.0"

# Habilitar las extensiones en el servidor (idempotente)
jupyter server extension enable --user jupyter_lsp
jupyter server extension enable --user jupyter_ai

echo "==> [server-ext] Extensiones instaladas y habilitadas ✓"

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
        ipywidgets \
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
        "jupyter-ai>=2.20.0,<3.0" \
        --quiet

    python -m ipykernel install --user --name=llm --display-name="Python (LLM - PyTorch + LangChain)"
    deactivate
    echo "==> [kernel:llm] Listo ✓"
else
    # Asegurar jupyter-ai en venv existente (idempotente)
    if ! "$VENV_BASE/llm/bin/pip" show jupyter-ai > /dev/null 2>&1; then
        echo "==> [kernel:llm] Instalando jupyter-ai en venv existente..."
        "$VENV_BASE/llm/bin/pip" install --no-cache-dir --quiet \
            "jupyter-ai>=2.20.0,<3.0" \
            "langchain-ollama>=0.2.0,<1.0"
    fi
    if ! "$VENV_BASE/llm/bin/pip" show ipywidgets > /dev/null 2>&1; then
        echo "==> [kernel:llm] Instalando ipywidgets en venv existente..."
        "$VENV_BASE/llm/bin/pip" install --no-cache-dir --quiet ipywidgets
    fi
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
        ipywidgets \
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
        "jupyter-ai>=2.20.0,<3.0" \
        "langchain-ollama>=0.2.0,<1.0" \
        --quiet

    python -m ipykernel install --user --name=ia --display-name="Python (IA - Scikit + TF + XGBoost)"
    deactivate
    echo "==> [kernel:ia] Listo ✓"
else
    # Asegurar jupyter-ai en venv existente (idempotente)
    if ! "$VENV_BASE/ia/bin/pip" show jupyter-ai > /dev/null 2>&1; then
        echo "==> [kernel:ia] Instalando jupyter-ai en venv existente..."
        "$VENV_BASE/ia/bin/pip" install --no-cache-dir --quiet \
            "jupyter-ai>=2.20.0,<3.0" \
            "langchain-ollama>=0.2.0,<1.0"
    fi
    if ! "$VENV_BASE/ia/bin/pip" show ipywidgets > /dev/null 2>&1; then
        echo "==> [kernel:ia] Instalando ipywidgets en venv existente..."
        "$VENV_BASE/ia/bin/pip" install --no-cache-dir --quiet ipywidgets
    fi
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
        ipywidgets \
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
        "jupyter-ai>=2.20.0,<3.0" \
        "langchain-ollama>=0.2.0,<1.0" \
        --quiet

    python -m ipykernel install --user --name=bigdata --display-name="Python (BigData - PySpark + Delta + MinIO)"
    deactivate
    echo "==> [kernel:bigdata] Listo ✓"
else
    # Asegurar jupyter-ai en venv existente (idempotente)
    if ! "$VENV_BASE/bigdata/bin/pip" show jupyter-ai > /dev/null 2>&1; then
        echo "==> [kernel:bigdata] Instalando jupyter-ai en venv existente..."
        "$VENV_BASE/bigdata/bin/pip" install --no-cache-dir --quiet \
            "jupyter-ai>=2.20.0,<3.0" \
            "langchain-ollama>=0.2.0,<1.0"
    fi
    if ! "$VENV_BASE/bigdata/bin/pip" show ipywidgets > /dev/null 2>&1; then
        echo "==> [kernel:bigdata] Instalando ipywidgets en venv existente..."
        "$VENV_BASE/bigdata/bin/pip" install --no-cache-dir --quiet ipywidgets
    fi
    echo "==> [kernel:bigdata] Ya existe, saltando."
fi

echo ""
echo "==> Kernels disponibles:"
jupyter kernelspec list
echo "==> Inicialización completada ✓"
