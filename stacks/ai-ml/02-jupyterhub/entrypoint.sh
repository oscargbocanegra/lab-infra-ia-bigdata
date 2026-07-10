#!/bin/sh
set -eu

read_secret() {
  secret_path="$1"

  if [ ! -r "$secret_path" ]; then
    echo "ERROR: secret no disponible o no legible: $secret_path" >&2
    exit 1
  fi

  tr -d "\r\n" < "$secret_path"
}

: "${JUPYTERHUB_DB_HOST:=postgres}"
: "${JUPYTERHUB_DB_PORT:=5432}"
: "${JUPYTERHUB_DB_NAME:=jupyterhub}"
: "${JUPYTERHUB_DB_USER:=jupyterhub}"
: "${JUPYTERHUB_DB_PASSWORD_FILE:=/run/secrets/jupyterhub_db_password}"
: "${JUPYTERHUB_COOKIE_SECRET_FILE:=/run/secrets/jupyterhub_cookie_secret}"

JUPYTERHUB_DB_PASSWORD="$(read_secret "$JUPYTERHUB_DB_PASSWORD_FILE")"

if [ -z "$JUPYTERHUB_DB_PASSWORD" ]; then
  echo "ERROR: el secret de PostgreSQL está vacío" >&2
  exit 1
fi

if [ ! -r "$JUPYTERHUB_COOKIE_SECRET_FILE" ]; then
  echo "ERROR: cookie secret no disponible o no legible" >&2
  exit 1
fi

export JUPYTERHUB_DB_PASSWORD
export JUPYTERHUB_COOKIE_SECRET_FILE

echo "Inicializando JupyterHub"
echo "PostgreSQL: ${JUPYTERHUB_DB_HOST}:${JUPYTERHUB_DB_PORT}/${JUPYTERHUB_DB_NAME}"

exec "$@"
