#!/bin/bash
set -e

echo "==> Iniciando configuración de Jupyter..."

# Ejecutar script de inicialización de kernels
if [ -f /tmp/init-kernels.sh ]; then
    bash /tmp/init-kernels.sh
fi

echo "==> Iniciando Jupyter Lab..."

# Ejecutar el comando original de Jupyter
exec start-notebook.sh "$@"
