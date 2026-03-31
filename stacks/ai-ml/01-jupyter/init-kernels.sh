#!/bin/bash
# ============================================================
# init-kernels.sh — Inicialización de kernels Jupyter
# ============================================================
# Kernels creados:
#   llm      → PyTorch + Transformers + LangChain + Ollama client
#   ia       → Scikit-learn + TF/Keras + XGBoost + OpenCV
#   bigdata  → PySpark + Delta Lake + MinIO (s3a) + Pandas + Dask
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
