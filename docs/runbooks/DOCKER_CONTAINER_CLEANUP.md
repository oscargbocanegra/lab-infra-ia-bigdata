# Docker Container Cleanup

## Objetivo

Evitar la acumulación de contenedores locales detenidos generados por reemplazos de tareas Docker Swarm.

## Alcance

El proceso considera únicamente contenedores en estado `created`, `exited` o `dead` con antigüedad superior a `RETENTION`.

No elimina imágenes, volúmenes, redes, servicios, stacks, secrets ni configs.

## Configuración

Archivo: `/etc/default/lab-docker-container-cleanup`

```text
APPLY=false
RETENTION=168h
REPORT_DIR=/var/log/lab-health/docker-cleanup
```

`APPLY=false` ejecuta inventario y reporte sin borrar.

## Programación

El timer se ejecuta diariamente a las 03:30 con un retraso aleatorio máximo de 15 minutos.

## Rollback

```bash
sudo systemctl disable --now lab-docker-container-cleanup.timer
```

La reparación de metadata bajo `/var/lib/docker` nunca se automatiza.

## Verificación posterior de candidatos

Antes de ejecutar `docker container prune`, el proceso conserva los
identificadores completos de todos los candidatos.

Después del prune valida individualmente cada identificador y reporta:

- `CANDIDATES_INITIAL`;
- `CANDIDATES_REMOVED`;
- `CANDIDATES_REMAINING`;
- `CANDIDATE_REMOVED=<id>`;
- `CANDIDATE_REMAINING=<id>`;
- `UNRESOLVED_CANDIDATES`.

Códigos de salida:

- `0`: ejecución correcta;
- `2`: permanece metadata en estado `dead`;
- `3`: permanece al menos un candidato inicial.

La reparación manual de metadata bajo `/var/lib/docker` permanece fuera
del alcance de esta automatización.
