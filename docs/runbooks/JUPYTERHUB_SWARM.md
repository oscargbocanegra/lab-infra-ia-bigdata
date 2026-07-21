# Runbook: JupyterHub sobre Docker Swarm

## Objetivo

Operar, verificar, desplegar y recuperar JupyterHub sin perder datos.

## Arquitectura

- Hub: `master1`.
- Single-users: `master2`.
- Base de datos: PostgreSQL en `master2`.
- Entrada LAN: Traefik mediante `jupyterhub.sexydad`.
- Redes: `public` e `internal`.
- Persistencia Hub: `/srv/fastdata/jupyterhub/hub`.
- Persistencia usuarios: `/srv/fastdata/jupyterhub/users`.
- Runtime single-user: `stacks/ai-ml/01-jupyter`.

## Servicios esperados

    jupyterhub_jupyterhub
    jupyterhub-user-ogiovanni
    jupyterhub-user-odavid

Los servicios `jupyterhub-user-*` son creados dinámicamente por
SwarmSpawner.

## Secrets requeridos

    jupyterhub_cookie_secret
    jupyterhub_db_password
    minio_access_key
    minio_secret_key

## Despliegue

Ejecutar desde `master1`:

    cd ~/lab-infra-ia-bigdata

    docker stack config       -c stacks/ai-ml/02-jupyterhub/stack.yml       >/dev/null

    docker stack deploy       --with-registry-auth       -c stacks/ai-ml/02-jupyterhub/stack.yml       jupyterhub

## Verificación

En `master1`:

    docker stack services jupyterhub

    docker service ls       --format '{{.Name}} {{.Replicas}} {{.Image}}' |
    grep -E '^jupyterhub'

    curl       --fail       --silent       --show-error       --insecure       --resolve 'jupyterhub.sexydad:443:127.0.0.1'       https://jupyterhub.sexydad/hub/health

Resultado esperado:

    jupyterhub_jupyterhub 1/1
    HTTP 200

## Verificación single-user

Validar:

- ejecución en `master2`;
- kernels Python, LLM, IA y BigData;
- JARVIS `/jarvis` y `%%JARVIS`;
- Ollama;
- GPU;
- MinIO;
- lectura y escritura en `/home/jovyan/work`;
- persistencia después de Stop/Start.

## Incidente conocido: timeout a 192.168.80.200:11434 desde notebook

Síntoma típico:

        ConnectTimeout ... host='192.168.80.200', port=11434 ... /api/tags

Causa raíz:

- `jupyter_jupyter_ai_config.json` persistido en el home del usuario con
    `fields.base_url` legacy (`http://192.168.80.200:11434`).
- Desde single-user en red `internal`, el endpoint correcto es
    `http://ollama:11434`.

Remediación:

1. Desplegar JupyterHub con el bootstrap `jupyterhub_singleuser_entrypoint_v2`.
2. Reiniciar el servidor del usuario en JupyterHub.
3. Verificar dentro del single-user:

        python - <<'PY'
        import json
        from pathlib import Path
        p = Path('/home/jovyan/.jupyter/jupyter_jupyter_ai_config.json')
        print(json.loads(p.read_text()).get('fields', {}).get('base_url'))
        PY

Resultado esperado:

        http://ollama:11434

Validación de conectividad interna:

        getent hosts ollama
        curl --max-time 15 http://ollama:11434/api/tags

## Rollback

1. Revertir el commit que causó la degradación.
2. Sincronizar `main` en `master1`.
3. Redesplegar JupyterHub.
4. Verificar health, login y persistencia.
5. No borrar `/srv/fastdata/jupyterhub`.

El stack JupyterLab standalone fue retirado. Restaurarlo exige recuperar
su definición desde el historial Git y justificarlo como cambio temporal.
