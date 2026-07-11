# ADR-011: JupyterHub multiusuario con SwarmSpawner y acceso al Docker Socket

## Estado

Aceptado, implementado y validado funcionalmente.

La aceptación integral de `odavid` y la retirada de los servicios legacy permanecen como tareas operativas posteriores.

## Fecha

2026-07-10.

## Contexto

El laboratorio opera sobre Docker Swarm con dos nodos:

- `master1`: manager y plano de control.
- `master2`: worker de cómputo, datos y GPU.

Actualmente siguen activos los servicios legacy:

- `jupyter_jupyter_ogiovanni`
- `jupyter_jupyter_odavid`

El objetivo es migrar gradualmente a JupyterHub multiusuario sin retirar los servicios legacy hasta completar la validación y la ventana de rollback.

## Decisión

Se adopta:

- JupyterHub `4.0.2`.
- DockerSpawner `13.0.0` con `SwarmSpawner`.
- NativeAuthenticator `1.3.0`.
- Configurable HTTP Proxy `4.6.3`.
- PostgreSQL como base de datos del Hub.
- Traefik para acceso mediante `jupyterhub.sexydad`.
- Docker Swarm Secrets para credenciales.

JupyterHub se ejecutará en `master1`.

Los servidores single-user se crearán en `master2` con:

```text
node.hostname == master2
node.labels.tier == compute
```

La eliminación de servicios single-user se controlará con:

```python
c.SwarmSpawner.remove_containers = True
```

## Persistencia

Cada usuario tendrá almacenamiento independiente en:

```text
/srv/fastdata/jupyterhub/users/<username>/work
/srv/fastdata/jupyterhub/users/<username>/.local
/srv/fastdata/jupyterhub/users/<username>/.venv
/srv/fastdata/jupyterhub/users/<username>/.cache
```

Política del datalake:

```text
/srv/datalake           -> solo lectura
/srv/datalake/datasets  -> solo lectura
/srv/datalake/notebooks -> lectura y escritura controlada
/srv/datalake/artifacts -> lectura y escritura controlada
```

El estado operativo local del Hub se almacenará en:

```text
/srv/fastdata/jupyterhub/hub
```

Las rutas deben existir previamente con permisos y propietarios verificados. Docker no debe crearlas automáticamente como `root`.

## Seguridad

El Hub requiere acceso al Docker Socket:

```text
/var/run/docker.sock:/var/run/docker.sock:ro
```

El modo `ro` no restringe los verbos de la API Docker. Un compromiso del Hub podría permitir crear o eliminar servicios, montar rutas del host, inspeccionar el clúster o interrumpir workloads.

El riesgo se clasifica como **alto**.

Mitigaciones:

- Hub restringido a `master1`.
- Acceso LAN-only.
- Sin puertos publicados directamente.
- Exposición únicamente mediante Traefik.
- Imagen inmutable.
- Secrets de Docker Swarm.
- Límites de CPU y memoria.
- Una sola réplica.
- Administradores restringidos.
- Servicios legacy preservados durante la migración.
- Git como fuente del estado deseado.
- Logging y revisión de creación y eliminación de servicios.

## Alternativas descartadas

- Docker Compose local: introduciría una plataforma paralela y drift.
- Kubernetes: fuera de la arquitectura aprobada.
- Hub en `master2`: mezclaría control plane con cargas pesadas y GPU.
- Servicios Jupyter estáticos: se conservan solo como rollback temporal.

Se evaluará posteriormente un Docker Socket Proxy, previa validación completa con `SwarmSpawner`.

## Recursos

Hub:

```text
Reserva: 0.25 CPU / 512 MiB
Límite: 1 CPU / 2 GiB
```

Single-user inicial:

```text
Reserva: 0.25 CPU / 512 MiB
Límite: 4 CPU / 8 GiB
```

## Despliegue

1. Validar Git y scaffold.
2. Publicar imagen inmutable.
3. Preparar persistencia del Hub.
4. Respaldar PostgreSQL.
5. Crear rol y base `jupyterhub`.
6. Crear Docker Swarm Secrets.
7. Validar redes y DNS.
8. Desplegar desde `master1`.
9. Validar healthcheck y logs.
10. Probar autenticación y spawn de `ogiovanni`.
11. Probar autenticación y spawn de `odavid`.
12. Validar persistencia y permisos.
13. Validar eliminación del servicio single-user.
14. Mantener servicios legacy durante la ventana de rollback.

## Rollback

Durante la migración:

- no eliminar los servicios Jupyter legacy;
- no eliminar sus rutas persistentes;
- no eliminar la nueva base, secrets o backups sin la confirmación literal `CONFIRMO BORRADO`.

Ante fallo:

1. retirar temporalmente el acceso al hostname nuevo;
2. revertir la imagen o escalar el Hub a cero;
3. comprobar que los servicios legacy continúan `1/1`;
4. redirigir usuarios a los hostnames legacy;
5. preservar PostgreSQL y las rutas de JupyterHub para diagnóstico.

## Criterios de aceptación

- JupyterHub funciona detrás de Traefik.
- El acceso permanece LAN-only.
- `ogiovanni` y `odavid` pueden autenticarse.
- Cada usuario obtiene un servicio en `master2`.
- Placement y límites son correctos.
- Los datos persisten después de recrear el servidor.
- El datalake general es de solo lectura.
- Notebooks y artifacts tienen escritura controlada.
- El servicio single-user se elimina al detenerlo.
- Los servicios legacy siguen disponibles durante rollback.
- Stack, ADR y runbook quedan versionados en Git.

## Estado de implementación

Corte operativo: `2026-07-11`.

- JupyterHub está desplegado en `master1` con una réplica saludable.
- La imagen del Hub está fijada por tag inmutable y digest.
- PostgreSQL contiene la base y las tablas de JupyterHub.
- Traefik publica `jupyterhub.sexydad` exclusivamente por HTTPS.
- Los endpoints `/hub/health`, `/hub/login` y `/hub/signup` responden HTTP `200`.
- El cookie secret de Swarm se copia a `/run/jupyterhub/jupyterhub_cookie_secret` con modo `0600`.
- Los Jupyter legacy continúan `1/1`.
- `ogiovanni` validó autenticación, spawn, placement, recursos, GPU, conectividad, mounts, escritura, Stop/Start y persistencia.
- `odavid` validó autorización, autenticación, spawn, placement en `master2`, UID/GID y GPU.
- `SwarmSpawner` eliminó el servicio anterior y creó uno nuevo durante el ciclo Stop/Start.
- Los Jupyter legacy continúan `1/1` como rollback.

## Control de despliegue

La reconciliación normal del stack se realiza mediante:

```text
.github/workflows/jupyterhub-deploy.yml
```

El workflow es manual, protegido por el environment `production`, exige la confirmación `DEPLOY`, se ejecuta en el runner de `master1` y verifica que los servicios legacy permanezcan sin cambios.

El workflow legacy `.github/workflows/deploy.yml` excluye los archivos de esta migración para impedir reconstrucciones o redespliegues accidentales de los Jupyter standalone.

## Consecuencias

Positivas:

- administración centralizada;
- servicios dinámicos;
- persistencia independiente;
- menor duplicación;
- control de recursos.

Negativas:

- privilegio elevado sobre Docker;
- dependencia de PostgreSQL y Docker API;
- mayor complejidad operativa;
- una sola réplica del Hub.

## Trabajo futuro

- evaluar Docker Socket Proxy;
- agregar métricas y alertas;
- validar asignación GPU;
- automatizar backup y restore;
- ejecutar pruebas periódicas de restauración.

## Evidencia de runtime NVIDIA

La implementación inicial usa el runtime NVIDIA predeterminado de `master2`.

Se validó que:

- la RTX 2080 Ti es visible en el host;
- la imagen single-user accede a la GPU;
- los Jupyter legacy ejecutados como servicios Swarm acceden a la GPU;
- `master2` posee la etiqueta `gpu=nvidia`;
- `master2` no declara Generic Resources para GPU.

Los servidores single-user declaran:

```text
NVIDIA_VISIBLE_DEVICES=0
NVIDIA_DRIVER_CAPABILITIES=compute,utility
CUDA_VISIBLE_DEVICES=0
```

Esta decisión deberá reevaluarse si se incorporan varias GPU o scheduling concurrente con aislamiento estricto.
