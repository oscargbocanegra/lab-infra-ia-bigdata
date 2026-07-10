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

Scaffold en validación. No desplegar hasta completar todos los prerrequisitos.

Los servicios legacy permanecen activos como rollback:

- `jupyter_jupyter_ogiovanni`;
- `jupyter_jupyter_odavid`.

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
giovannotti/lab-jupyterhub:sha-960cb595
```

### Single-user

```text
giovannotti/lab-jupyter:sha-0cbf11c
```

La imagen del Hub debe publicarse en un registry antes del despliegue.

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
11. Servicios legacy en `1/1`.

## Despliegue

El despliegue se realizará únicamente desde `master1` cuando todos los prerrequisitos estén aprobados.

```bash
docker stack deploy --with-registry-auth -c stacks/ai-ml/02-jupyterhub/stack.yml jupyterhub
```

No ejecutar durante la fase de scaffold.

## Rollback

Durante la migración se preservan los servicios legacy.

El rollback inicial reversible consiste en escalar el Hub a cero y volver temporalmente a los accesos anteriores.

No ejecutar `docker stack rm`, borrar secrets, bases, rutas o backups sin la confirmación literal `CONFIRMO BORRADO`.

## Documentación relacionada

- ADR: `docs/adrs/ADR-011-jupyterhub-swarmspawner-docker-socket.md`.
- Runbook: `docs/runbooks/JUPYTERHUB_SWARM.md`.
