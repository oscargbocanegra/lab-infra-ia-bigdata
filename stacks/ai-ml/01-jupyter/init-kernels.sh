#!/bin/bash
set -e

KERNEL_DIR="/home/jovyan/.local/share/jupyter/kernels"

# Función para verificar si un kernel existe
kernel_exists() {
    [ -d "$KERNEL_DIR/$1" ]
}

# Instalar kernel LLM si no existe
if ! kernel_exists "llm"; then
    echo "==> Creando kernel LLM..."
    python -m venv /home/jovyan/.venv/llm
    source /home/jovyan/.venv/llm/bin/activate
    
    pip install --upgrade pip setuptools wheel
    
    pip install --no-cache-dir ipykernel
    
    pip install --no-cache-dir \
        torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121
    
    pip install --no-cache-dir \
        transformers \
        accelerate \
        bitsandbytes \
        sentencepiece \
        protobuf \
        datasets \
        peft \
        trl \
        langchain \
        openai \
        tiktoken
    
    python -m ipykernel install --user --name=llm --display-name="Python (LLM)"
    deactivate
    echo "==> Kernel LLM creado exitosamente"
else
    echo "==> Kernel LLM ya existe"
fi

# Instalar kernel IA si no existe
if ! kernel_exists "ia"; then
    echo "==> Creando kernel IA..."
    python -m venv /home/jovyan/.venv/ia
    source /home/jovyan/.venv/ia/bin/activate
    
    pip install --upgrade pip setuptools wheel
    
    pip install --no-cache-dir \
        ipykernel \
        numpy \
        pandas \
        matplotlib \
        seaborn \
        scikit-learn \
        scipy \
        jupyter
    
    pip install --no-cache-dir \
        torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121
    
    pip install --no-cache-dir \
        tensorflow \
        keras \
        opencv-python-headless \
        pillow \
        plotly \
        xgboost \
        lightgbm \
        catboost
    
    python -m ipykernel install --user --name=ia --display-name="Python (IA)"
    deactivate
    echo "==> Kernel IA creado exitosamente"
else
    echo "==> Kernel IA ya existe"
fi

echo "==> Inicialización de kernels completada"
