# Propuesta de arquitectura y optimización — laboratorio IA & Big Data

**Fecha:** 2026-08-21
**Alcance:** laboratorio de aprendizaje para dos usuarios; no plataforma productiva.

## Decisión ejecutiva

Se recomienda conservar Docker Swarm y la topología de dos nodos. La separación
actual entre control/acceso (`master1`) y datos, cómputo y GPU (`master2`) es
correcta para el tamaño del laboratorio. El foco de mejora no debe ser migrar a
Kubernetes, sino hacer reproducible el runtime, proteger la capacidad de
`master2` y formalizar contratos de datos y recursos.

## Arquitectura objetivo

```text
LAN privada -> DNS local *.sexydad -> Traefik (master1)
                                       |
       +-------------------------------+------------------------------+
       |                                                              |
master1: control y acceso                                  master2: datos y cómputo
- Swarm manager, Traefik, Portainer                        - PostgreSQL + pgvector
- Prometheus, Grafana, JupyterHub                           - MinIO (bronze/silver/gold)
- Airflow web/scheduler, Spark master/history               - OpenSearch, Qdrant
                                                            - Spark y Airflow worker
                                                            - Jupyter single-user
                                                            - Ollama + RTX 2080 Ti

Jupyter/Airflow -> Spark -> MinIO -> consumo analítico/ML
                      |-> PostgreSQL, Qdrant u OpenSearch según el caso
                      |-> Ollama, con inferencias GPU serializadas
```

## Prioridades de refactorización

### P0 — Fuente de verdad y operación reproducible

1. Generar en cada despliegue un inventario de servicios, imágenes, réplicas,
   placement, límites y healthchecks; compararlo con los `stack.yml`.
2. Declarar `docs/architecture/STATE.md` como estado operativo vigente y
   reconciliar los documentos históricos que aún describen JupyterLab legacy.
3. Usar tags inmutables o digests para imágenes ejecutables; no usar `latest`.
4. Añadir un smoke test por stack: healthcheck, dependencia mínima y métrica
   Prometheus asociada.

### P1 — Presupuesto de recursos de `master2`

`master2` concentra 32 GB de RAM, 16 hilos, GPU de 11 GB y los servicios
stateful; no puede sostener de forma segura los máximos de Spark, dos sesiones
Jupyter y Ollama al mismo tiempo.

| Clase | Política |
|---|---|
| Base: PostgreSQL, MinIO, OpenSearch, Qdrant | Reservas fijas; no compiten con usuarios. |
| Interactiva: Jupyter/Open WebUI/RAG | Máximo dos sesiones, con 4 CPU y 6–8 GiB iniciales por sesión. |
| Batch: Spark/Airflow | Una ejecución pesada a la vez, mediante pool de Airflow. |
| GPU: Ollama/notebooks | Un solo propietario por práctica; Jupyter CPU por defecto. |

Acciones: crear pools Airflow `spark=1`, `gpu=1` y `default`; iniciar Spark
con 8 cores y 8 GiB; ofrecer perfil Jupyter GPU bajo demanda; alertar al 80 %
de disco; y medir antes de elevar límites. El criterio de éxito es conservar al
menos 20 % de RAM disponible durante una carga representativa sin OOM ni
restarts inesperados.

### P2 — Datos, gobierno y reproducibilidad

- Mantener MinIO como contrato canónico: `bronze` inmutable, `silver` validado
  y `gold` consumible.
- Usar Parquet/Delta, particionado y esquemas/expectativas versionados junto al
  pipeline.
- Evitar duplicar datos sin necesidad: PostgreSQL para transacciones y
  metadatos, Qdrant para recuperación vectorial y OpenSearch para logs y
  búsqueda.
- Mantener OpenMetadata como componente de prácticas de gobierno, después de
  validar MinIO -> Spark -> Airflow.

### P3 — Red y seguridad pragmática

- Reemplazar `/etc/hosts` por DNS local wildcard `*.sexydad -> master1`.
- Mantener Traefik como único ingreso y restringir los accesos directos a
  PostgreSQL y Ollama con UFW/DOCKER-USER.
- Introducir un Docker Socket Proxy antes de ampliar JupyterHub: un socket
  montado como solo lectura no restringe las operaciones de la API Docker.
- Mantener secrets de Swarm, rotación documentada y comprobaciones para que no
  aparezcan credenciales en logs.

## Plan incremental

| Fase | Resultado verificable |
|---|---|
| 1. Baseline | Inventario runtime/Git, dashboard de capacidad y smoke tests. |
| 2. Admisión | Pools Airflow y perfiles Jupyter; cargas pesadas serializadas. |
| 3. Datos | Pipeline idempotente Bronze -> Silver -> Gold con calidad y linaje. |
| 4. Red/seguridad | DNS local, revisión de puertos y Socket Proxy validado. |
| 5. Opcionales | MLOps, gobierno, streaming o AWS emulado aislados y reversibles. |

Cada fase debe modificar un stack por vez, medir antes y después y conservar el
manifiesto anterior para rollback sin eliminar datos ni secrets.

## Evaluación de Floci

### Recomendación

**No implementarlo como servicio permanente del clúster ni como reemplazo de
MinIO, Spark, Airflow o Docker Swarm.** Sí vale la pena un piloto aislado si el
laboratorio necesita aprender o probar SDK AWS, Terraform/OpenTofu, CDK,
Testcontainers o integraciones con S3, SQS, Lambda e IAM.

Floci es un emulador local de APIs AWS y expone servicios compatibles en el
puerto 4566. Para ciertos servicios usa contenedores Docker reales, por lo que
requiere acceso al socket Docker. Esto resulta útil en desarrollo y CI, pero
añade superficie de privilegio y competencia por recursos si se instala en la
plataforma compartida.

| Necesidad | Decisión |
|---|---|
| Data lake, transformación y orquestación reales | Mantener MinIO + Spark + Airflow; no usar Floci. |
| RAG e inferencia local | Mantener Qdrant/pgvector + Ollama; no usar Floci. |
| Pruebas de una app que usa S3/SQS/Lambda/IAM | Piloto Floci aislado en portátil o CI. |
| Aprender IaC AWS | Piloto Floci por proyecto de práctica. |
| Emular EKS/ECS/RDS | Solo entorno efímero y con necesidad concreta. |

### Condiciones del piloto

1. Ejecutarlo fuera de los stacks permanentes, preferiblemente en la estación
   de desarrollo o en CI efímero.
2. Fijar una versión de imagen, no `floci/floci:latest`.
3. Usar `memory` para CI; `hybrid` o `wal` y un volumen dedicado solo cuando la
   práctica requiera persistencia.
4. No exponer el puerto 4566 a la LAN.
5. Si se concede socket Docker, no montar secrets del laboratorio y destruir el
   entorno al terminar.
6. Medir valor con un test de integración reproducible antes de adoptar nada:
   crear bucket S3 y cola SQS, invocar Lambda y ejecutarlo en CI.

**Decisión de adopción:** aprobar únicamente un piloto de una práctica AWS
concreta. Si no reduce el tiempo de aprendizaje o no habilita una prueba que
hoy no existe, retirarlo.

## Referencias

- Estado vigente: `docs/architecture/STATE.md`.
- Propuesta vigente: `PROPUESTA_MIGRACION_VIGENTE.md`.
- [Repositorio y documentación de Floci](https://github.com/floci-io/floci).
- [Release 1.7.0 de Floci](https://github.com/floci-io/floci/releases/tag/v1.7.0).
