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

stage_cookie_secret() {
  source_file="$1"
  runtime_file="$2"
  runtime_dir="${runtime_file%/*}"
  temporary_file="${runtime_file}.tmp.$$"

  if [ "$source_file" = "$runtime_file" ]; then
    echo "ERROR: el cookie secret fuente y runtime no pueden usar la misma ruta" >&2
    exit 1
  fi

  if [ ! -r "$source_file" ]; then
    echo "ERROR: cookie secret no disponible o no legible: $source_file" >&2
    exit 1
  fi

  if [ "$runtime_dir" = "$runtime_file" ]; then
    echo "ERROR: ruta runtime inválida para el cookie secret: $runtime_file" >&2
    exit 1
  fi

  install -d -m 0700 "$runtime_dir"
  chmod 0700 "$runtime_dir"

  umask 077
  tr -d "\r\n" < "$source_file" > "$temporary_file"

  if [ ! -s "$temporary_file" ]; then
    echo "ERROR: el cookie secret está vacío" >&2
    exit 1
  fi

  chmod 0600 "$temporary_file"
  mv -f "$temporary_file" "$runtime_file"
  chmod 0600 "$runtime_file"

  if [ "$(stat -c '%a' "$runtime_dir")" != "700" ]; then
    echo "ERROR: el directorio runtime del cookie secret no tiene modo 0700" >&2
    exit 1
  fi

  if [ "$(stat -c '%a' "$runtime_file")" != "600" ]; then
    echo "ERROR: el cookie secret runtime no tiene modo 0600" >&2
    exit 1
  fi
}

: "${JUPYTERHUB_DB_HOST:=postgres}"
: "${JUPYTERHUB_DB_PORT:=5432}"
: "${JUPYTERHUB_DB_NAME:=jupyterhub}"
: "${JUPYTERHUB_DB_USER:=jupyterhub}"
: "${JUPYTERHUB_DB_PASSWORD_FILE:=/run/secrets/jupyterhub_db_password}"

COOKIE_SECRET_SOURCE="${JUPYTERHUB_COOKIE_SECRET_SOURCE_FILE:-${JUPYTERHUB_COOKIE_SECRET_FILE:-/run/secrets/jupyterhub_cookie_secret}}"
COOKIE_SECRET_RUNTIME="${JUPYTERHUB_COOKIE_SECRET_RUNTIME_FILE:-/run/jupyterhub/jupyterhub_cookie_secret}"

JUPYTERHUB_DB_PASSWORD="$(read_secret "$JUPYTERHUB_DB_PASSWORD_FILE")"

if [ -z "$JUPYTERHUB_DB_PASSWORD" ]; then
  echo "ERROR: el secret de PostgreSQL está vacío" >&2
  exit 1
fi

stage_cookie_secret "$COOKIE_SECRET_SOURCE" "$COOKIE_SECRET_RUNTIME"

export JUPYTERHUB_DB_PASSWORD
export JUPYTERHUB_COOKIE_SECRET_FILE="$COOKIE_SECRET_RUNTIME"

echo "Inicializando JupyterHub"
echo "PostgreSQL: ${JUPYTERHUB_DB_HOST}:${JUPYTERHUB_DB_PORT}/${JUPYTERHUB_DB_NAME}"
echo "Cookie secret preparado en almacenamiento efímero privado"

exec "$@"
