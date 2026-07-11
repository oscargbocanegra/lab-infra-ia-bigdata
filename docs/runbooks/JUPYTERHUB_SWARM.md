# Runbook: JupyterHub multiusuario sobre Docker Swarm

## Objetivo

Operar, verificar, recuperar y revertir JupyterHub sin afectar los servicios Jupyter legacy ni perder datos.

## Arquitectura

- Hub: `master1`.
- Single-user servers: `master2`.
- Base de datos: PostgreSQL en `master2`.
- Acceso: Traefik mediante `jupyterhub.sexydad`.
- Redes: `public` e `internal`.
- Persistencia de usuarios: `/srv/fastdata/jupyterhub/users`.
- Estado local del Hub: `/srv/fastdata/jupyterhub/hub`.
- Servicios legacy preservados para rollback.

## Componentes esperados

```text
jupyterhub_jupyterhub
jupyterhub-user-ogiovanni
jupyterhub-user-odavid
jupyter_jupyter_ogiovanni
jupyter_jupyter_odavid
```

Los servicios `jupyterhub-user-*` existen únicamente mientras el servidor de cada usuario esté iniciado.

## Prerrequisitos

Antes del despliegue verificar:

1. Rama Git aprobada y sin cambios inesperados.
2. Imagen inmutable publicada.
3. Redes `public` e `internal` disponibles.
4. PostgreSQL saludable.
5. Backup reciente de PostgreSQL.
6. Rol y base `jupyterhub` creados.
7. Secrets `jupyterhub_cookie_secret` y `jupyterhub_db_password` disponibles.
8. Directorios persistentes creados con propietarios y permisos correctos.
9. Servicios legacy en estado `1/1`.

## Baseline no destructivo

### En `master1`

```bash
cd ~/lab-infra-ia-bigdata
git status -sb
docker node ls
docker network ls --filter name=public --filter name=internal
docker secret ls
docker service ls
docker service ls --format "{{.Name}} {{.Replicas}}" | grep -E "jupyter|postgres|traefik"
```

Resultado esperado:

- `master1` es Leader.
- `master2` está Ready y Active.
- Redes `public` e `internal` presentes.
- Traefik y PostgreSQL saludables.
- Ambos Jupyter legacy en `1/1`.

### En `master2`

```bash
hostname
findmnt /srv/fastdata
findmnt /srv/datalake
find /srv/fastdata/jupyterhub/users -maxdepth 2 -type d -printf "%u:%g %m %p\n" | sort
find /srv/datalake -maxdepth 1 -type d -printf "%u:%g %m %p\n" | sort
```

No modificar propietarios ni permisos durante una verificación ordinaria.

## Despliegue controlado

### Mecanismo primario: GitHub Actions

1. Fusionar una rama aprobada en `main`.
2. Verificar que `JupyterHub CI` finalizó correctamente.
3. Abrir GitHub Actions y seleccionar `Deploy JupyterHub`.
4. Ejecutar el workflow sobre `main`.
5. Escribir `DEPLOY` en el parámetro de confirmación.
6. Aprobar el environment `production` cuando la protección lo requiera.
7. Revisar el resumen y la evidencia generada por el workflow.

El workflow se ejecuta en el runner self-hosted de `master1` y reconcilia exclusivamente el stack `jupyterhub`.

### Recuperación controlada desde `master1`

Usar solo cuando GitHub Actions no esté disponible y registrar toda la salida en `~/lab-reports`:

```bash
cd ~/lab-infra-ia-bigdata
docker stack config   -c stacks/ai-ml/02-jupyterhub/stack.yml   >/dev/null
docker stack deploy   --with-registry-auth   -c stacks/ai-ml/02-jupyterhub/stack.yml   jupyterhub
```

No recrear secrets, base de datos o persistencia durante una reconciliación ordinaria.

## Verificación técnica

### Estado del servicio

```bash
docker stack services jupyterhub
docker service ps jupyterhub_jupyterhub --no-trunc
docker service inspect jupyterhub_jupyterhub --pretty
docker service logs --since 10m --timestamps jupyterhub_jupyterhub
```

Resultado esperado:

- Réplicas `1/1`.
- Task ejecutándose en `master1`.
- Sin errores de secrets, PostgreSQL, proxy o configuración.

### Verificación HTTP

```bash
curl --fail --silent --show-error   --resolve 'jupyterhub.sexydad:443:127.0.0.1'   --insecure   https://jupyterhub.sexydad/hub/health
```

Resultado esperado: respuesta HTTP satisfactoria del healthcheck.

## Verificación de GitHub Actions

En `master1`, antes y después de una reconciliación:

```bash
docker service inspect jupyterhub_jupyterhub   --format '{{.Spec.TaskTemplate.ContainerSpec.Image}}'

for service in   jupyter_jupyter_ogiovanni   jupyter_jupyter_odavid
do
  docker service inspect "$service"     --format '{{.Spec.Name}} {{.Spec.TaskTemplate.ContainerSpec.Image}}'
done
```

La imagen real de JupyterHub debe coincidir con la imagen fijada por digest en `stack.yml`. Los servicios legacy deben conservar sus imágenes y permanecer en `1/1`.

## Validación funcional

Validar por separado con `ogiovanni` y `odavid`:

1. Acceso al portal.
2. Registro o autenticación.
3. Autorización administrativa cuando aplique.
4. Inicio del servidor single-user.
5. Servicio creado en `master2`.
6. Acceso de lectura y escritura en el directorio personal.
7. Datalake general en solo lectura.
8. Escritura controlada en notebooks y artifacts.
9. Acceso a Ollama, Spark y demás dependencias autorizadas.
10. Persistencia después de detener y recrear el servidor.

## Verificación de placement

### En `master1`

```bash
docker service ls --format "{{.Name}} {{.Replicas}}" | grep "^jupyterhub-user-"
docker service ps jupyterhub-user-ogiovanni --no-trunc
docker service ps jupyterhub-user-odavid --no-trunc
```

Cada servicio single-user debe ejecutarse exclusivamente en `master2`.

## Verificación de recursos

```bash
docker service inspect jupyterhub-user-ogiovanni --format "{{json .Spec.TaskTemplate.Resources}}"
docker service inspect jupyterhub-user-odavid --format "{{json .Spec.TaskTemplate.Resources}}"
```

Valores iniciales esperados:

- Reserva: 0.25 CPU y 512 MiB.
- Límite: 4 CPU y 8 GiB.

## Prueba de persistencia

En el notebook del usuario crear un archivo identificable dentro de `/home/jovyan/work`.

Después:

1. detener el servidor desde JupyterHub;
2. confirmar que el servicio `jupyterhub-user-<usuario>` fue eliminado;
3. iniciar nuevamente el servidor;
4. confirmar que el archivo continúa disponible.

No eliminar manualmente el servicio durante esta prueba.

## Diagnóstico

### Hub no inicia

Revisar en orden:

1. disponibilidad de la imagen;
2. secrets;
3. conexión a PostgreSQL;
4. permisos de `/srv/fastdata/jupyterhub/hub`;
5. acceso al Docker Socket;
6. redes overlay;
7. logs del servicio.

### Single-user no inicia

Revisar:

1. imagen single-user disponible en `master2`;
2. labels y placement constraints;
3. capacidad de CPU, RAM y GPU;
4. rutas persistentes;
5. propietarios y permisos;
6. red `internal`;
7. resolución del Hub;
8. logs del Hub y task del servicio de usuario.

### Error de autenticación

Revisar:

1. estado del usuario en NativeAuthenticator;
2. autorización administrativa;
3. bloqueos por intentos fallidos;
4. base de datos del Hub;
5. cookie secret persistente.

## Contención

Ante degradación del Hub:

1. impedir nuevos inicios de sesión;
2. preservar logs;
3. no eliminar servicios, secrets, base de datos ni directorios;
4. validar que los servicios legacy siguen `1/1`;
5. redirigir temporalmente a los hostnames legacy.

## Rollback reversible

La opción inicial es escalar el Hub a cero, preservando todo su estado:

```bash
docker service scale jupyterhub_jupyterhub=0
```

Después verificar:

```bash
docker service ls --format "{{.Name}} {{.Replicas}}" | grep -E "jupyterhub|jupyter_jupyter"
```

Los servicios legacy deben permanecer disponibles.

Escalar nuevamente el Hub:

```bash
docker service scale jupyterhub_jupyterhub=1
```

No ejecutar `docker stack rm jupyterhub`, eliminar secrets, borrar la base o retirar directorios sin la confirmación literal `CONFIRMO BORRADO`.

## Backup

El backup debe incluir:

- base PostgreSQL `jupyterhub`;
- configuración versionada en Git;
- inventario de secrets, sin exportar su contenido;
- `/srv/fastdata/jupyterhub/hub`;
- rutas de usuarios conforme a la política de retención.

Todo backup debe tener fecha, ubicación, retención y procedimiento de restore.

## Cierre del cambio

El cambio puede cerrarse únicamente con evidencia de:

- Hub `1/1`;
- autenticación funcional;
- spawn en `master2`;
- persistencia validada;
- permisos del datalake validados;
- eliminación automática de servicios single-user;
- servicios legacy preservados;
- stack, ADR y runbook versionados;
- backup y rollback documentados.

## Preflight GPU y permisos

Antes del despliegue:

1. validar `nvidia-smi` en `master2`;
2. validar `nvidia-smi` dentro de la imagen single-user;
3. validar acceso GPU dentro de un servicio Swarm legacy;
4. comprobar lectura/escritura como UID `1000` y GID `100`;
5. confirmar datalake y datasets como solo lectura;
6. confirmar notebooks y artifacts como lectura/escritura;
7. preservar un backup de ACL antes de cualquier ajuste.

El rollback de ACL debe ejecutarse mediante el archivo generado con `getfacl --recursive --absolute-names`.

## Evidencia de aceptación — 2026-07-11

### `ogiovanni`

Validación completa de autenticación, spawn dinámico, placement en `master2`, UID/GID, límites de recursos, GPU, conectividad interna, mounts, escritura, recreación de tarea, Stop/Start desde JupyterHub y persistencia.

### `odavid`

Validación completa de autorización, autenticación, spawn dinámico, placement en `master2`, UID/GID, GPU, conectividad interna, mounts, escritura, eliminación y recreación del servicio dinámico, Stop/Start y persistencia con verificación de hash SHA-256.

### Rollback

Los servicios `jupyter_jupyter_ogiovanni` y `jupyter_jupyter_odavid` permanecen `1/1`. Su retirada requiere una ventana posterior y la confirmación literal `CONFIRMO BORRADO`.
