# JupyterHub multiusuario sobre Docker Swarm

## Propósito

Este stack implementa JupyterHub multiusuario para el laboratorio AI/Big Data.

La arquitectura separa:

- plano de control en `master1`;
- servidores single-user en `master2`;
- persistencia de usuarios en `/srv/fastdata`;
- acceso al datalake en `/srv/datalake`;
- publicación mediante Traefik;
- estado del Hub en PostgreSQL.

## Estado

JupyterHub está operativo y validado funcionalmente en `master1`. `ogiovanni` y `odavid` completaron la aceptación funcional integral.

Estado verificado:

- `jupyterhub_jupyterhub` en `1/1`;
- PostgreSQL inicializado para JupyterHub;
- Traefik publica `jupyterhub.sexydad` por `websecure` con TLS;
- `/hub/health`, `/hub/login` y `/hub/signup` responden HTTP `200`;
- el cookie secret de Swarm se transforma en un archivo efímero privado `0600`;
- `ogiovanni` completó autenticación, spawn, placement, GPU, conectividad, Stop/Start y persistencia;
- `odavid` completó autorización, autenticación, spawn, placement, UID/GID, GPU, conectividad, Stop/Start y persistencia;
- `SwarmSpawner` eliminó y recreó correctamente el servicio single-user durante el ciclo Stop/Start.

El stack JupyterLab standalone fue retirado. JupyterHub es el acceso Jupyter canónico:


## Componentes

| Componente | Versión | Función |
|---|---:|---|
| JupyterHub | 4.0.2 | Portal, autenticación y control de sesiones |
| DockerSpawner | 13.0.0 | Integración con Docker Swarm |
| NativeAuthenticator | 1.2.0 | Autenticación local |
| Configurable HTTP Proxy | 4.6.3 | Proxy interno de JupyterHub |
| PostgreSQL | 16 | Persistencia del estado del Hub |

## Archivos

```text
stacks/ai-ml/02-jupyterhub/
├── .dockerignore
├── .gitignore
├── Dockerfile
├── README.md
├── entrypoint.sh
├── jupyterhub_config.py
├── requirements.txt
└── stack.yml
```

## Distribución por nodos

### `master1`

- servicio `jupyterhub_jupyterhub`;
- Configurable HTTP Proxy;
- acceso al Docker Socket;
- publicación por Traefik;
- una réplica.

### `master2`

- servicios dinámicos `jupyterhub-user-<username>`;
- datos persistentes de usuarios;
- datasets, modelos y datalake;
- acceso a GPU y servicios de cómputo.

## Redes

El stack utiliza redes overlay externas:

- `public`: conexión con Traefik;
- `internal`: comunicación con PostgreSQL, Hub y servicios internos.

No se publican puertos directamente.

## Hostname

```text
jupyterhub.sexydad
```

El acceso debe permanecer LAN-only.

## Imágenes

### Hub

```text
giovannotti/lab-jupyterhub:sha-c171d2a9@sha256:a7c047fcdd635cdb0754b3068654b51e43be6097d8650dd0342719a90bae1db6
```

### Single-user

```text
giovannotti/lab-jupyter:sha-0cbf11c
```

La imagen del Hub está publicada y fijada por tag inmutable y digest de registry.

## Persistencia

### Hub

```text
/srv/fastdata/jupyterhub/hub
```

### Usuarios

```text
/srv/fastdata/jupyterhub/users/<username>/work
/srv/fastdata/jupyterhub/users/<username>/.local
/srv/fastdata/jupyterhub/users/<username>/.venv
/srv/fastdata/jupyterhub/users/<username>/.cache
```

### Datalake

```text
/srv/datalake           -> solo lectura
/srv/datalake/datasets  -> solo lectura
/srv/datalake/notebooks -> lectura/escritura controlada
/srv/datalake/artifacts -> lectura/escritura controlada
```

Las rutas deben existir previamente en `master2`. Docker no debe crearlas automáticamente como `root`.

## Secrets requeridos

```text
jupyterhub_cookie_secret
jupyterhub_db_password
minio_access_key
minio_secret_key
```

Los secrets se declaran como externos y no deben almacenarse en Git.

## Variables principales

| Variable | Descripción |
|---|---|
| `JUPYTERHUB_DB_HOST` | Host PostgreSQL |
| `JUPYTERHUB_DB_PORT` | Puerto PostgreSQL |
| `JUPYTERHUB_DB_NAME` | Base del Hub |
| `JUPYTERHUB_DB_USER` | Rol PostgreSQL |
| `JUPYTERHUB_DB_PASSWORD_FILE` | Secret con contraseña |
| `JUPYTERHUB_COOKIE_SECRET_FILE` | Secret criptográfico de cookies |
| `JUPYTERHUB_HUB_CONNECT_URL` | URL interna del Hub |
| `JUPYTERHUB_NETWORK_NAME` | Red overlay de usuarios |
| `JUPYTERHUB_SINGLEUSER_IMAGE` | Imagen single-user |

## Recursos

### Hub

```text
Reserva: 0.25 CPU / 512 MiB
Límite: 1 CPU / 2 GiB
```

### Single-user

```text
Reserva: 0.25 CPU / 512 MiB
Límite: 4 CPU / 8 GiB
```

## Seguridad

El Hub monta:

```text
/var/run/docker.sock:/var/run/docker.sock:ro
```

Este acceso implica privilegios elevados sobre Docker y el clúster. El modo `ro` no restringe los verbos de la API Docker.

Consultar:

- `docs/adrs/ADR-011-jupyterhub-swarmspawner-docker-socket.md`;
- `docs/runbooks/JUPYTERHUB_SWARM.md`.

## Validación local de la imagen

```bash
docker build -t lab-jupyterhub:validation stacks/ai-ml/02-jupyterhub
docker run --rm --entrypoint jupyterhub lab-jupyterhub:validation --version
docker run --rm --entrypoint configurable-http-proxy lab-jupyterhub:validation --version
```

Versiones esperadas:

```text
JupyterHub 4.0.2
Configurable HTTP Proxy 4.6.3
```

## Validación del stack

```bash
docker stack config -c stacks/ai-ml/02-jupyterhub/stack.yml >/dev/null
```

Este comando valida la sintaxis, pero no comprueba que imágenes, secrets, redes, rutas o PostgreSQL existan.

## Prerrequisitos de despliegue

1. Imagen del Hub publicada con tag inmutable.
2. Imagen single-user disponible en `master2`.
3. Redes `public` e `internal` existentes.
4. PostgreSQL saludable.
5. Backup reciente de PostgreSQL.
6. Rol y base `jupyterhub` creados.
7. Secrets creados.
8. Persistencia del Hub preparada en `master1`.
9. Persistencia de usuarios preparada en `master2`.
10. Permisos y ACL verificados.
11. Imagen single-user disponible en `master2`.

## Despliegue

El mecanismo primario de reconciliación es GitHub Actions:

```text
.github/workflows/jupyterhub-deploy.yml
```

Características:

- ejecución manual mediante `workflow_dispatch`;
- confirmación literal `DEPLOY`;
- runner self-hosted en `master1`;
- environment `production`;
- validación de redes, secrets, persistencia, PostgreSQL y Traefik;
- despliegue exclusivo del stack `jupyterhub`;
- validación de imagen, placement y endpoints HTTPS;
- validación de que JupyterHub permanece saludable.

El comando directo queda reservado para recuperación controlada desde `master1` y debe generar evidencia en `~/lab-reports`:

```bash
docker stack deploy   --with-registry-auth   -c stacks/ai-ml/02-jupyterhub/stack.yml   jupyterhub
```

## Rollback

Durante la migración se preservan los servicios legacy.

El rollback inicial reversible consiste en escalar el Hub a cero y volver temporalmente a los accesos anteriores.

No ejecutar `docker stack rm`, borrar secrets, bases, rutas o backups sin la confirmación literal `CONFIRMO BORRADO`.

## Documentación relacionada

- ADR: `docs/adrs/ADR-011-jupyterhub-swarmspawner-docker-socket.md`.
- Runbook: `docs/runbooks/JUPYTERHUB_SWARM.md`.

## Validación de runtime GPU y DNS

La validación previa al despliegue confirmó:

- `master2` utiliza el runtime Docker `nvidia` como predeterminado;
- los servicios `jupyterhub-user-*` acceden correctamente a la RTX 2080 Ti;
- la imagen single-user ejecuta `nvidia-smi`;
- los servidores dinámicos usan `NVIDIA_VISIBLE_DEVICES=0`;
- las capacidades autorizadas son `compute,utility`;
- los aliases internos `postgres`, `ollama` y `spark_master` resuelven y aceptan conexión dentro de la red `internal`.

La asignación GPU depende del placement en `master2`, del runtime NVIDIA del nodo y de las variables NVIDIA. El nodo no utiliza actualmente Generic Resources de Swarm para la GPU.

<!-- COOKIE_SECRET_STAGING:README -->

### Preparación privada del cookie secret

Docker Swarm monta el secret fuente en `/run/secrets/jupyterhub_cookie_secret`.

El entrypoint copia el contenido normalizado a `/run/jupyterhub/jupyterhub_cookie_secret`, crea `/run/jupyterhub` con modo `0700`, aplica modo `0600` al archivo y exporta esa ruta como `JUPYTERHUB_COOKIE_SECRET_FILE`.

Variables:
- `JUPYTERHUB_COOKIE_SECRET_SOURCE_FILE`: secret fuente de Swarm.
- `JUPYTERHUB_COOKIE_SECRET_RUNTIME_FILE`: ruta efímera privada opcional.
- `JUPYTERHUB_COOKIE_SECRET_FILE`: archivo runtime entregado a JupyterHub.

El archivo runtime es efímero y no debe almacenarse en Git, logs, backups ni en el volumen persistente del Hub.

Router HTTPS: `websecure` con `tls=true`. El entrypoint `web` redirige globalmente hacia HTTPS.

<!-- JUPYTERHUB_RUNTIME_PARITY_START -->
## Paridad funcional single-user

La paridad funcional de JupyterHub fue validada el 2026-07-11
para los usuarios `ogiovanni` y `odavid`.

Capacidades disponibles:

- kernels `llm`, `ia` y `bigdata`;
- kernels base Python, Julia y R;
- JARVIS mediante `/jarvis` y `%%JARVIS`;
- Jupyter AI con Ollama;
- acceso a GPU en `master2`;
- secretos MinIO mediante Docker Swarm Secrets;
- persistencia independiente de `work`, `.local`, `.venv`
  y `.cache`.

El bootstrap single-user se entrega mediante:

- `jupyterhub_singleuser_entrypoint_v2`;
- `jupyterhub_singleuser_init_kernels_v1`.

Para exponer los kernels persistentes se mantiene:

`c.Spawner.disable_user_config = False`

Las rutas canónicas son:

- `/srv/fastdata/jupyterhub/users/<username>/work`;
- `/srv/fastdata/jupyterhub/users/<username>/.local`;
- `/srv/fastdata/jupyterhub/users/<username>/.venv`;
- `/srv/fastdata/jupyterhub/users/<username>/.cache`.
<!-- JUPYTERHUB_RUNTIME_PARITY_END -->


## Retirada de JupyterLab standalone

La decisión está documentada en:

    docs/adrs/ADR-013-retirada-jupyterlab-legacy.md

El directorio `stacks/ai-ml/01-jupyter` se conserva únicamente como
contexto de construcción de la imagen single-user.
