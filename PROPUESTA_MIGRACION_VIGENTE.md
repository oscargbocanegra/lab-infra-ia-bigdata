# Propuesta maestra de migración, refactorización y mejora
## IT-Lab IA & Big Data

**Versión:** 2.2
**Fecha de actualización:** 2026-07-16
**Estado:** vigente — ejecución incremental orientada a funcionamiento
**Aprobada por el usuario:** 2026-07-16
**Repositorio fuente de verdad:** `oscargbocanegra/lab-infra-ia-bigdata`

---

# 0. Ajuste operativo aprobado para esta ejecución

Esta propuesta se ejecutará como un laboratorio de aprendizaje, no como una
plataforma productiva. La prioridad es que los servicios que ya existen
funcionen de forma reproducible con el menor cambio posible. Por tanto:

- No se optimizará alta disponibilidad, capacidad, RPO/RTO ni escalado antes
  de recuperar los servicios funcionales.
- No se harán migraciones destructivas de datos ni se retirarán servicios
  stateful hasta contar con una prueba funcional del reemplazo.
- Se trabajará en bloques pequeños: una causa, un cambio, una validación y un
  rollback.
- Una tarea solo se marcará `[x]` cuando exista evidencia runtime; la
  presencia de un stack en Git no equivale a despliegue operativo.
- Si un servicio no es necesario para el siguiente ejercicio de aprendizaje,
  se mantendrá sin refactorizar y se documentará como pendiente.

## Secuencia mínima de ejecución

1. Recuperar y validar `rag-api` (`1/1`, `/health` y una operación mínima de
   almacenamiento).
2. Añadir únicamente healthchecks o recursos de los servicios que se usen o
   que causen inestabilidad observable.
3. Ejecutar un laboratorio mínimo MinIO → Spark → Airflow, validando cada
   dependencia antes de continuar.
4. Dejar OpenMetadata, observabilidad avanzada, GraphRAG y optimización de
   modelos para después de tener una ruta de aprendizaje funcional.

El rollback de cada bloque será redeploy del manifiesto anterior y restauración
del servicio a su réplica estable. No se eliminarán volúmenes ni secretos como
parte del rollback normal.

---

# 1. Objetivo

Mantener y mejorar un laboratorio doméstico de dos nodos para que dos usuarios puedan aprender, practicar y construir proyectos de:

- Arquitecturas Big Data.
- Ingeniería y transformación de datos.
- Inteligencia artificial local.
- RAG, GraphRAG y búsqueda vectorial.
- Orquestación de pipelines.
- Observabilidad, logging y operación de infraestructura.
- Gobierno y catálogo de datos.
- Infraestructura como código y Docker Swarm.

El laboratorio no tiene requisitos productivos de alta disponibilidad ni conservación histórica de datos. Los componentes stateful pueden recrearse desde cero cuando una refactorización lo requiera. Se preservarán el código, la configuración, los secretos y la evidencia técnica necesaria; no se crearán proyectos complejos de backup o restore de datos que no aporten al aprendizaje actual.

---

# 2. Decisiones aprobadas

- [x] Mantener Docker Swarm como orquestador.
- [x] Mantener `master1` como Manager, Leader y plano de control.
- [x] Mantener `master2` como nodo de datos, cómputo, persistencia y GPU.
- [x] Mantener los servicios desplegados permanentemente; no se implementará encendido/apagado manual ni escalado a cero como estrategia normal.
- [x] Mantener GitHub como fuente del estado objetivo.
- [x] Mantener Google Drive para propuesta, inventarios, evidencias y reportes operativos.
- [x] Mantener Traefik como gateway y Portainer como consola operativa.
- [x] Mantener Prometheus y Grafana para métricas.
- [x] Mantener OpenSearch y OpenSearch Dashboards para logs, búsquedas, trazas y experimentos que lo justifiquen.
- [x] Mantener inicialmente el patrón físico `docker-logs-*` y enriquecer los eventos con campos semánticos.
- [x] Mantener Qdrant para búsqueda vectorial y laboratorios GraphRAG o de relaciones construidas en la capa de aplicación.
- [x] Reconocer que Qdrant es una base vectorial, no una base de grafos nativa.
- [x] Utilizar Spark como motor principal de procesamiento, transformación y experimentación con datos.
- [x] Utilizar Airflow para orquestar pipelines.
- [x] Utilizar MinIO como almacenamiento de objetos y base para arquitectura Medallion.
- [x] Consolidar bases de aplicaciones en una instancia PostgreSQL compartida con bases y usuarios separados.
- [x] Refactorizar OpenMetadata para utilizar PostgreSQL y el OpenSearch principal.
- [x] No migrar datos históricos de MySQL/OpenSearch exclusivos de OpenMetadata; el catálogo podrá comenzar desde cero y volver a ingerir las fuentes.
- [x] Descartar Authentik y el alcance SSO.
- [x] No implementar Health Agent hasta que exista un caso de uso concreto no cubierto por Prometheus, Grafana, Portainer y los smoke tests.
- [x] No desplegar Alertmanager independiente mientras Grafana Alerting cubra las necesidades del laboratorio.
- [x] Tratar todo cambio nuevo como migración, refactorización o mejora incremental sobre el estado ya alcanzado.

## Exclusiones

- Alta disponibilidad productiva.
- Clúster de tres o más nodos por resiliencia.
- Authentik, SSO u otro proveedor de identidad centralizado.
- Backups empresariales, RPO/RTO y pruebas periódicas de disaster recovery.
- Migración de datos históricos sin valor para el aprendizaje.
- Encendido y apagado manual de stacks como operación cotidiana.
- Separar cada servicio en una instancia de base de datos o buscador propia.

---

# 3. Estado funcional alcanzado

## P1-R1 — Reconciliación de imágenes

- [x] Reconciliar Open WebUI entre Git y runtime.
- [x] Actualizar Open WebUI a `v0.10.2`.
- [x] Reconciliar Portainer Server y Agent.
- [x] Obtener `IMAGE_DRIFT=0`.
- [x] Fusionar PR #10.

## P1-R2 — GPU, Ollama y NVIDIA Exporter

- [x] Actualizar el driver NVIDIA.
- [x] Instalar y validar NVIDIA Container Toolkit.
- [x] Validar GPU dentro de contenedores.
- [x] Recuperar Ollama y NVIDIA Exporter.
- [x] Validar métricas GPU en Prometheus.
- [x] Ejecutar inferencia local con GPU.
- [x] Documentar la implementación.
- [x] Fusionar PR #11.

## P1-R3 — Open WebUI

- [x] Desplegar la imagen aprobada.
- [x] Validar servicio, health y ausencia de OOM.
- [x] Validar conexión con PostgreSQL.
- [x] Validar conexión con Ollama y protección LAN.

## P1-R4 — Servicios residuales

- [x] Inventariar servicios residuales.
- [x] Eliminar servicios `secret-printer-*` autorizados.
- [x] Preservar Docker Secrets legítimos.
- [x] Documentar la evidencia.

## P1-R5 — Paridad Docker Engine

- [x] Actualizar ambos nodos a Docker Engine `29.6.1`.
- [x] Recuperar y validar el Swarm.
- [x] Documentar el procedimiento.
- [x] Fusionar PR #12.

## JupyterHub multiusuario

- [x] Mantener JupyterHub en `master1`.
- [x] Crear servidores single-user dinámicos en `master2`.
- [x] Configurar `SwarmSpawner` y `NativeAuthenticator`.
- [x] Crear persistencia independiente para `ogiovanni` y `odavid`.
- [x] Crear base y rol PostgreSQL dedicados.
- [x] Validar login, spawn, persistencia, kernels y conectividad.
- [x] Retirar Jupyter standalone como plataforma principal.
- [x] Versionar configuración y documentación.

## OpenSearch, métricas y logging

- [x] Mantener OpenSearch principal en `master2`.
- [x] Validar clúster en estado green.
- [x] Ejecutar Fluent Bit en ambos nodos.
- [x] Validar logs de `master1` y `master2`.
- [x] Mantener Prometheus/Grafana para métricas.
- [x] Mantener OpenSearch/Dashboards para logs.

## Plataforma base disponible

- [x] PostgreSQL/pgvector.
- [x] MinIO.
- [x] OpenSearch y OpenSearch Dashboards.
- [x] Qdrant.
- [x] Ollama.
- [x] RAG API y Agent.
- [x] Airflow.
- [x] Spark.
- [x] JupyterHub.
- [x] Open WebUI.
- [x] Prometheus y Grafana.
- [x] OpenMetadata.
- [x] n8n.

---

# 4. Arquitectura objetivo

## 4.1 master1 — control, acceso y coordinación

| Servicio | Función | Reserva objetivo | Límite objetivo | Estado |
|---|---|---:|---:|---|
| Traefik | Gateway HTTP/HTTPS | 0.10 CPU / 128 MB | 0.50 CPU / 512 MB | Permanente |
| Portainer Server | Administración visual | 0.10 CPU / 128 MB | 0.50 CPU / 512 MB | Permanente |
| Portainer Agent | Agente global | 0.05 CPU / 32 MB | 0.20 CPU / 128 MB | Permanente/global |
| Prometheus | Métricas | 0.25 CPU / 512 MB | 1 CPU / 1.5 GB | Permanente |
| Grafana | Dashboards y alertas de métricas | 0.10 CPU / 128 MB | 0.50 CPU / 512 MB | Permanente |
| Node Exporter | Métricas del nodo | 0.05 CPU / 32 MB | 0.20 CPU / 128 MB | Permanente/global |
| cAdvisor | Métricas de contenedores | 0.05 CPU / 64 MB | 0.30 CPU / 256 MB | Permanente/global |
| Fluent Bit | Envío de logs | 0.05 CPU / 32 MB | 0.25 CPU / 128 MB | Permanente/global |
| JupyterHub | Acceso multiusuario | 0.25 CPU / 512 MB | 1 CPU / 2 GB | Permanente |
| Airflow Webserver | Interfaz de pipelines | 0.50 CPU / 1 GB | 2 CPU / 2 GB | Permanente |
| Airflow Scheduler | Planificación | 0.50 CPU / 512 MB | 2 CPU / 2 GB | Permanente |
| Airflow Flower | Monitoreo de workers | 0.10 CPU / 128 MB | 0.50 CPU / 512 MB | Permanente |
| Redis | Cola de Airflow | 0.10 CPU / 128 MB | 1 CPU / 512 MB | Permanente |
| Spark Master | Coordinación Spark | 0.50 CPU / 1 GB | 2 CPU / 2 GB | Permanente |
| Spark History | Historial Spark | 0.25 CPU / 512 MB | 1 CPU / 1 GB | Permanente |
| Open WebUI | Interfaz IA | 0.25 CPU / 512 MB | 2 CPU / 2 GB | Permanente |
| RAG API | API de recuperación | 0.25 CPU / 256 MB | 2 CPU / 2 GB | Permanente |
| Agent | Agentes y herramientas | 0.25 CPU / 256 MB | 2 CPU / 2 GB | Permanente |
| OpenMetadata Server | Catálogo y gobierno | 0.50 CPU / 1 GB | 2 CPU / 4 GB | Permanente |
| OpenSearch Dashboards | Exploración de logs | 0.50 CPU / 1 GB | 2 CPU / 3 GB | Permanente |

## 4.2 master2 — datos, cómputo, persistencia y GPU

| Servicio | Función | Reserva objetivo | Límite objetivo | Estado |
|---|---|---:|---:|---|
| PostgreSQL/pgvector | Bases de aplicaciones y metadatos | 0.50 CPU / 512 MB | 2 CPU / 2 GB | Permanente |
| OpenSearch | Logs, trazas y búsqueda compartida | 1 CPU / 3 GB | 4 CPU / 8 GB | Permanente |
| MinIO | Data lake y objetos | 0.50 CPU / 512 MB | 2 CPU / 2 GB | Permanente |
| Qdrant | Vectores, RAG y GraphRAG | 0.25 CPU / 512 MB | 2 CPU / 3 GB | Permanente |
| Ollama | Inferencia local con GPU | 1 CPU / 1 GB | 8 CPU / 16 GB | Permanente; modelos cargados según uso |
| n8n | Automatización | 0.25 CPU / 512 MB | 2 CPU / 2 GB | Permanente |
| Airflow Worker | Ejecución de tareas | 1 CPU / 1 GB | 4 CPU / 4 GB | Permanente |
| Spark Worker | Transformación y cómputo de datos | 1 CPU / 2 GB | 8 CPU / 10 GB | Permanente |
| Jupyter `ogiovanni` | Entorno de trabajo | 0.50 CPU / 1 GB | 4 CPU / 6 GB | Por sesión automática |
| Jupyter `odavid` | Entorno de trabajo | 0.50 CPU / 1 GB | 4 CPU / 6 GB | Por sesión automática |
| NVIDIA Exporter | Métricas GPU | 0.05 CPU / 32 MB | 0.10 CPU / 64 MB | Permanente |
| Node Exporter | Métricas del nodo | 0.05 CPU / 32 MB | 0.20 CPU / 128 MB | Permanente/global |
| cAdvisor | Métricas de contenedores | 0.05 CPU / 64 MB | 0.30 CPU / 256 MB | Permanente/global |
| Fluent Bit | Envío de logs | 0.05 CPU / 32 MB | 0.25 CPU / 128 MB | Permanente/global |
| Portainer Agent | Agente de gestión | 0.05 CPU / 32 MB | 0.20 CPU / 128 MB | Permanente/global |

## 4.3 Principios de capacidad

- Los límites representan máximos y pueden estar sobreasignados; no equivalen al consumo permanente.
- Las reservas deben permitir que todos los servicios base sean programados simultáneamente.
- El objetivo es conservar al menos 20 % de RAM libre durante una sesión normal de dos usuarios.
- Ollama, Spark y Jupyter pueden permanecer encendidos, pero sus cargas intensivas deben respetar límites para evitar que un único proceso monopolice `master2`.
- Spark deberá configurarse inicialmente con `SPARK_WORKER_CORES=8` y `SPARK_WORKER_MEMORY=8g`, dejando memoria adicional para el proceso JVM y el contenedor.
- OpenSearch utilizará inicialmente heap de 2 GB después de consolidar OpenMetadata; el ajuste definitivo dependerá de métricas de heap, GC, latencia y disco.
- Los valores objetivo deberán validarse con una línea base posterior al despliegue.

---

# 5. Topología de datos objetivo

## 5.1 PostgreSQL único en master2

```text
PostgreSQL
├── n8n
├── airflow
├── rag
├── openwebui
├── openmetadata
├── jupyterhub
└── mlflow          # futuro opcional para prácticas MLOps
```

Usuarios separados:

```text
n8n
airflow
rag
openwebui
openmetadata
jupyterhub
mlflow             # futuro
```

Reglas:

- Una base independiente por aplicación.
- Un usuario independiente por aplicación.
- No usar la base administrativa `postgres` como base de una aplicación.
- Conservar inicialmente los nombres reales de roles utilizados por los stacks.
- Utilizar Docker Swarm Secrets.
- Aplicar privilegio mínimo.
- No crear la base ni el usuario `authentik`.

## 5.2 OpenMetadata refactorizado

Arquitectura objetivo:

```text
OpenMetadata Server / master1
        |
        +---- PostgreSQL compartido / base openmetadata / master2
        |
        +---- OpenSearch compartido / clusterAlias openmetadata-lab / master2
```

Decisión de datos:

- No migrar el contenido del MySQL actual.
- No migrar los índices del OpenSearch exclusivo actual.
- Crear desde cero la base `openmetadata` y su usuario en PostgreSQL.
- Conectar OpenMetadata al OpenSearch principal.
- Volver a registrar e ingerir las fuentes del laboratorio.
- Validar catálogo, búsqueda, lineage e ingestiones.
- Después de la validación y con autorización explícita, retirar `openmetadata-mysql` y `openmetadata-es`.

## 5.3 Qdrant

Qdrant permanecerá como servicio especializado para:

- Colecciones de embeddings.
- RAG y búsqueda semántica.
- GraphRAG cuando las relaciones se modelen en la aplicación y los vectores se almacenen en Qdrant.
- Comparaciones entre estrategias de recuperación.
- Laboratorios de filtros, payloads, similitud y memoria vectorial.

No se duplicarán automáticamente las mismas colecciones vectoriales en PostgreSQL, Qdrant y OpenSearch. Cada experimento deberá indicar cuál es su vector store principal.

## 5.4 Spark y plataforma de datos

Spark será el motor principal para:

- Ingesta y transformación de datos.
- Limpieza y normalización.
- Procesamiento batch.
- DataFrames y Spark SQL.
- Prácticas de particionamiento.
- Procesos Bronze, Silver y Gold.
- Preparación de datos para IA.
- Integración con MinIO, PostgreSQL y JupyterHub.

Airflow orquestará las ejecuciones; MinIO almacenará los datos; PostgreSQL conservará control, auditoría y metadatos técnicos; OpenMetadata catalogará datasets y lineage.

---

# 6. Gobierno de OpenSearch e índices

## 6.1 Responsabilidades

| Información | Plataforma |
|---|---|
| Métricas de infraestructura y servicios | Prometheus |
| Dashboards de métricas y alertas | Grafana |
| Logs de Docker y aplicaciones | OpenSearch |
| Exploración de logs | OpenSearch Dashboards |
| Trazas de RAG y agentes | OpenSearch |
| Índices del catálogo | OpenMetadata sobre OpenSearch compartido |
| Vectores RAG/GraphRAG | Qdrant |

## 6.2 Convención inicial

| Uso | Patrón |
|---|---|
| Logs Docker | `docker-logs-*` |
| Trazas RAG | `rag-traces-*` |
| Trazas de agentes | `agent-traces-*` |
| Experimentos | `lab-experiments-*` |
| OpenMetadata | Índices administrados por OpenMetadata con `clusterAlias=openmetadata-lab` |

Los logs Docker se enriquecerán con los campos:

```text
service.name
stack.name
node.name
environment
log.dataset
container.name
```

No se crearán índices diarios separados para cada servicio mientras el volumen no lo justifique. Los dashboards utilizarán filtros y campos semánticos. Cualquier cambio futuro de `docker-logs-*` se realizará con plantillas y alias, no mediante un cambio directo que rompa las consultas existentes.

---

# 7. Plan vigente de refactorización

## P1-R6 — Seguridad de puertos directos

**Objetivo:** permitir solamente los accesos LAN realmente necesarios.

- [x] Inventariar puertos, UFW y `DOCKER-USER`.
- [x] Reemplazar la regla LAN general por reglas específicas.
- [x] Permitir PostgreSQL `5432/tcp` desde la LAN autorizada.
- [x] Permitir Ollama `11434/tcp` desde la LAN autorizada.
- [x] Restringir MinIO `9000/tcp`: publicación Swarm residual bloqueada por la política IPv4 exacta; riesgo bajo aceptado para el laboratorio.
- [x] Conservar tráfico `ESTABLISHED,RELATED`.
- [x] Actualizar scripts y documentación de red mediante PR #17.
- [x] Aplicar por una ventana controlada con snapshot y rollback automático.
- [!] No repetir pruebas desde Windows/IPv6; cobertura sustituida por política exacta y pruebas funcionales aceptadas.
- [x] Generar reporte `.txt` de evidencia de la aplicación IPv4.
- [x] Cerrar mediante PR, validación del runtime y aceptación documentada del riesgo residual.

### Checkpoint P1-R6 — aplicación IPv4 DOCKER-USER (2026-07-17)

- Evidencia aceptada: `P1-R6-apply-docker-user-ipv4-master2-20260717_003700.txt`.
- Fuente: PR #17 fusionado; merge SHA `d20b63e47e58bff9270d94450c81097c6c8e2548`.
- Política activa: `LIVE_POLICY=DESIRED_EXACT`.
- Política persistente: `PERSISTENT_POLICY=DESIRED_EXACT`.
- PostgreSQL, Ollama, MinIO, Swarm y tráfico Docker interno: validados.
- Rollback: no ejecutado; no requerido.
- IPv6: hallazgo no bloqueante documentado; no repetir pruebas.
- Solicitud 10: `docker stack deploy` desde `main` no retiró `PublishedPort=9000`; rollback exitoso y MinIO `1/1`.
- No repetir Solicitud 10.
- Solicitud 10A: `docker service update --publish-rm 9000 minio_minio` fue aceptado y convergió, pero la inspección posterior siguió mostrando `tcp:9000:9000:host`; rollback exitoso y MinIO `1/1`.
- No repetir Solicitud 10A.
- Solicitud 10B confirmó `SPEC_AND_ENDPOINT_RETAIN_PORT`; MinIO siguió `1/1` en `master2`.
- Decisión aprobada: conservar el producto funcional, no recrear ni eliminar MinIO y aceptar el drift como riesgo residual controlado por `DOCKER-USER`.
- Estado P1-R6: Finalizada.

### Checkpoint P1-R6 — Solicitud 10 con rollback (2026-07-17)

- Evidencia: `P1-R6-redeploy-minio-from-main-master1-20260717_010109.txt`.
- `origin/main` y manifiesto sin puertos: validados.
- Resultado: `PORTS_AFTER=tcp:9000:9000:host`; el drift permaneció.
- Protección: `ROLLBACK_EXECUTED=YES`, `ROLLBACK_RESULT=SUCCESS`.
- Estado de MinIO posterior: `1/1`.
- Decisión: usar la operación explícita `--publish-rm 9000`; no repetir el redespliegue.

### Checkpoint P1-R6 — Solicitud 10A con rollback (2026-07-17)

- Evidencia: `P1-R6-remove-minio-published-port-master1-20260717_011053.txt`.
- Resultado: la actualización fue aceptada y el servicio convergió, pero `PORTS_AFTER=tcp:9000:9000:host`.
- Protección: rollback automático ejecutado con resultado `SUCCESS`.
- Estado de MinIO posterior: `1/1` en `master2`.
- Decisión: no repetir 10/10A; ejecutar una inspección 10B de `.Spec.EndpointSpec.Ports` y `.Endpoint.Ports`, sin cambios de runtime.

### Cierre P1-R6 — riesgo residual aceptado (2026-07-17)

- Evidencia 10B: `P1-R6-inspect-minio-spec-endpoint-master1-20260717_012035.txt`.
- Clasificación: `SPEC_AND_ENDPOINT_RETAIN_PORT` en T0 y T+15 segundos.
- Estado funcional: MinIO `1/1`, tarea Running en `master2`; política IPv4 activa/persistente exacta y tráfico interno previamente validado.
- Control compensatorio: nuevas conexiones IPv4 a `192.168.80.200:9000` se bloquean explícitamente en `DOCKER-USER`.
- Decisión: no recrear un servicio stateful funcional; aceptar el drift como deuda técnica de baja prioridad del laboratorio.
- Reapertura: únicamente ante evidencia de acceso no autorizado, pérdida de persistencia del firewall o regresión funcional.
- Progreso maestro: `8/15 = 53,3 %`.
- Siguiente actividad: P1-R7 — Healthchecks y recursos.

## P1-R7 — Recuperación funcional, healthchecks y recursos

**Objetivo:** recuperar primero los servicios degradados y aplicar solo los
healthchecks y recursos necesarios para mantener estable el laboratorio.

- [x] Inventariar healthchecks reales por servicio mediante Solicitud 11.
- [x] Resolver `rag-api_rag-api=0/1` y validar `/health`.
- [x] Validar autenticación MinIO desde el contenedor de RAG API sin revelar secretos.
- [x] Añadir o corregir healthchecks de los servicios que se modifiquen.
- [x] Añadir límites a Traefik, Portainer Server, Portainer Agent y n8n.
- [x] Ajustar Ollama a una reserva baja y un límite compatible con los dos usuarios.
- [x] Ajustar Spark Worker a 8 cores y 8 GB de memoria Spark dentro de un límite de 10 GB.
- [x] Ajustar Jupyter single-user a límites iniciales de 4 CPU y 6 GB por usuario.
- [ ] Ajustar OpenSearch para la consolidación de OpenMetadata solo si P1-R8 se inicia.
- [x] Desplegar los cambios por grupos pequeños.
- [x] Ejecutar smoke tests después de cada grupo.
- [x] Medir RAM, CPU, disco, heap, GPU y réplicas.
- [x] Generar reportes `.txt` de ambos nodos.
- [ ] Actualizar documentación, PR y checklist.

### Checkpoint P1-R7 — inventario Swarm (2026-07-17)

- Evidencia: `P1-R7-inventory-healthchecks-resources-swarm-master1-20260717_013157.txt`.
- Fuente: `origin/main=d20b63e47e58bff9270d94450c81097c6c8e2548`.
- Nodos: `master1` Leader Ready/Active y `master2` Ready/Active; Docker 29.6.1.
- Servicios: 36; 35 en réplica deseada y un fallo real, `rag-api_rag-api=0/1`.
- Brechas: 33 sin healthcheck Docker; cinco sin límites y reservas.
- Excepción inicial: `airflow_airflow_init=0/0` es one-shot y no se considera degradado.
- Decisión: diagnosticar únicamente RAG API antes de modificar healthchecks o recursos.
- Criterio práctico: no exigir healthcheck idéntico a todos los servicios; aceptar verificaciones funcionales equivalentes o excepciones justificadas del laboratorio.
- Estado P1-R7: técnicamente completado; el cierre administrativo está en PR #19.

### Checkpoint P1-R7 — diagnóstico RAG API (2026-07-17)

- Evidencia: `P1-R7-diagnose-rag-api-master1-20260717_014009.txt`.
- Resultado: `SERVICE_STILL_DEGRADED`; réplicas `0/1` y endpoint `/health` HTTP 404.
- PostgreSQL/pgvector y Qdrant inicializan correctamente.
- Causa aislada: MinIO rechaza la autenticación con `SignatureDoesNotMatch` para `rag-documents`.
- Los manifiestos de MinIO y RAG API usan los mismos nombres externos de secretos, pero falta confirmar si sus servicios conservan los mismos IDs de objetos después de posibles rotaciones.
- Decisión: no reiniciar MinIO ni rotar credenciales a ciegas; comparar únicamente metadatos de secretos mediante Solicitud 13.
- P1-R7 permanece En curso; RAG API es un fallo funcional real, no una excepción de healthcheck.

### Checkpoint P1-R7 — referencias de secretos (2026-07-17)

- Evidencia: `P1-R7-compare-minio-rag-secret-ids-master1-20260717_014741.txt`.
- Resultado: MinIO y RAG API usan los mismos IDs actuales de `minio_access_key` y `minio_secret_key`.
- Decisión: descartar la rotación o actualización de secretos como corrección; no resolvería el fallo.
- Pendiente único: comprobar en `master2` si MinIO acepta sus secretos montados por localhost y por `minio:9000`, sin revelar valores ni modificar estado.

### Checkpoint P1-R7 — diagnóstico MinIO en worker (2026-07-17)

- Evidencia: `P1-R7-validate-minio-mounted-secret-auth-master2-20260717_015350.txt`.
- Resultado: abortado antes de la prueba con `SERVICE_NOT_FOUND`; `master2` es worker y no expone `docker service inspect`.
- No hubo cambio runtime ni evidencia nueva sobre autenticación.
- Decisión: no repetir 14; usar Solicitud 14A, que opera solo sobre el contenedor local de MinIO en `master2`.

### Checkpoint P1-R7 — imagen MinIO mínima (2026-07-17)

- Evidencia: `P1-R7-validate-minio-mounted-secret-auth-worker-master2-20260717_015826.txt`.
- MinIO confirmó `running` y `healthy` en ambas redes overlay.
- La Solicitud 14A abortó antes de autenticar porque la imagen no incluye `awk`; no hubo cambio runtime.
- Decisión: no repetir 14A; usar Solicitud 14B, que requiere únicamente `mc` y `/bin/sh` dentro del contenedor.

### Checkpoint P1-R7 — precheck MinIO (2026-07-17)

- Evidencia: `P1-R7-validate-minio-auth-mc-worker-master2-20260717_020358.txt`.
- MinIO continúa `running` y `healthy`.
- La Solicitud 14B abortó antes de autenticar durante el precheck interno; no hubo evidencia de fallo de credenciales ni cambio runtime.
- Decisión: no repetir 14B; inspeccionar mounts, rutas y healthcheck mediante Solicitud 14C, sin depender de utilidades internas opcionales.

### Checkpoint P1-R7 — recuperación MinIO/RAG y recursos (2026-07-17)

- Evidencia en nodos: `~/lab-reports/P1-R7-recreate-minio-secrets-master1-20260716_220811.txt`,
  `~/lab-reports/P1-R7-resources-master1-20260716_221233.txt` y
  `~/lab-reports/P1-R7-resources-master2-20260716_221233.txt`,
  `~/lab-reports/P1-R7-capacity-master1-20260716_221423.txt` y
  `~/lab-reports/P1-R7-capacity-master2-20260716_221423.txt`.
- Causa confirmada: la tarea activa de MinIO no tenía `/run/secrets`, aunque el
  servicio Swarm declaraba ambos secretos. RAG sí montaba los mismos IDs y por
  eso recibía `SignatureDoesNotMatch`.
- Corrección aplicada: recreación controlada únicamente de `minio_minio`,
  conservando `/srv/datalake/minio`, sin borrar datos, secretos ni volúmenes.
- Validación: MinIO montó los secretos, RAG autenticó contra
  `rag-documents`, `/health` respondió HTTP 200 y una escritura/lectura/
  eliminación temporal fue exitosa.
- Recursos aplicados: Traefik, Portainer Server/Agent, n8n, Ollama, Spark
  Worker y Jupyter single-user según los límites iniciales de esta propuesta.
  RAG API y n8n incorporan healthcheck Docker; MinIO ya tenía healthcheck.
- Estado runtime: `rag-api`, `minio`, `n8n`, `ollama`, `spark`, `jupyterhub`,
  Traefik y Portainer convergieron; Ollama requirió esperar la recreación de la
  imagen y terminó `1/1`.
- Cierre administrativo: cambios versionados y PR #19 abierto con checks
  automáticos exitosos.
- Medición posterior: master1 reportó 24 GiB disponibles y `/srv` al 1%;
  master2 reportó 25 GiB disponibles, `/srv/fastdata` al 7% y
  `/srv/datalake` al 3%; la RTX 2080 Ti estaba sin carga (0/11264 MiB).

### Estado de revisión de la propuesta — 2026-07-16

- La revisión inicial quedó resuelta en el checkpoint de recuperación de
  MinIO/RAG del 2026-07-17.
- `rag-api_rag-api=1/1`, el healthcheck Docker está `healthy` y `/health`
  responde HTTP 200 con PostgreSQL y Qdrant operativos.
- La autenticación MinIO desde el contenedor de RAG API fue demostrada sin
  revelar secretos; una operación temporal de escritura/lectura/eliminación
  también fue exitosa.
- La tarea defectuosa de MinIO fue recreada sin eliminar su persistencia. Los
  secretos quedaron montados correctamente.
- Los límites y healthchecks de P1-R7 fueron aplicados por grupos y medidos.
- Permanecen fuera de esta ejecución la refactorización stateful P1-R8 y la
  transformación completa Bronze → Silver → Gold de P2-R1.

### Avance consolidado — 2026-07-17

- Checklist documentado: `104` elementos completados de `170` (`61,2 %`);
  existe un elemento marcado como riesgo aceptado y `65` pendientes.
- Hitos maestros: `8/15` (`53,3 %`) completados antes de contabilizar P2-R1.
- P2-R1 tiene completados los prerrequisitos de buckets, ingesta Bronze,
  Spark distribuido y validación Bronze en Airflow; las transformaciones y
  auditoría permanecen pendientes.
- El porcentaje de hito no se mezcla con el porcentaje de checklist: el
  primero mide bloques principales y el segundo tareas detalladas.

## P1-R8 — Refactorización stateful (posterior a la recuperación funcional)

**Objetivo:** colocar la persistencia principal en `master2` y eliminar dependencias duplicadas.

**Riesgo específico de OpenMetadata:** bajo. Es un laboratorio sin datos productivos y el catálogo puede recrearse. La condición de cierre no es conservar datos históricos, sino dejar el servicio completamente funcional sobre PostgreSQL y OpenSearch compartidos.

- [ ] Crear ADR de topología stateful objetivo, solo después de cerrar P1-R7.
- [ ] Mover Qdrant a `master2` conservando una colección nueva o vacía.
- [ ] Crear base y usuario PostgreSQL para OpenMetadata.
- [ ] Refactorizar OpenMetadata para PostgreSQL.
- [ ] Configurar OpenMetadata con el OpenSearch compartido.
- [ ] Definir `clusterAlias=openmetadata-lab`.
- [ ] Iniciar OpenMetadata con catálogo nuevo.
- [ ] Volver a ingerir las fuentes del laboratorio.
- [ ] Validar servicio `1/1`, UI y API.
- [ ] Validar esquema en PostgreSQL e índices aislados en OpenSearch.
- [ ] Validar búsqueda, catálogo, lineage e ingestiones con al menos una fuente.
- [ ] Confirmar ausencia de errores persistentes de base de datos o búsqueda.
- [ ] Confirmar que las políticas de logs no afectan los índices de OpenMetadata.
- [ ] Retirar MySQL y OpenSearch exclusivos de OpenMetadata después de autorización explícita.
- [ ] Validar réplicas, placement, discos y consumo.
- [ ] Generar reporte `.txt` de estado final.
- [ ] Actualizar mapas de arquitectura y cerrar mediante PR.

## P2-R1 — Plataforma Spark y Medallion

- [x] Definir buckets o prefijos `bronze`, `silver` y `gold` en MinIO.
- [x] Crear proyecto de ingesta batch de ejemplo.
- [x] Crear transformación Bronze a Silver mínima con Airflow/pandas.
- [x] Crear transformación Silver a Gold mínima con Airflow/pandas.
- [x] Orquestar el pipeline mínimo con Airflow.
- [ ] Ejecutar desde JupyterHub y desde Airflow.
- [x] Registrar auditoría de ejecución en PostgreSQL.
- [ ] Publicar datasets y lineage en OpenMetadata.
- [ ] Crear plantilla reutilizable para nuevas fuentes.
- [ ] Documentar particionamiento, reejecución y manejo de errores.

### Checkpoint P2-R1 — capacidad mínima validada (2026-07-17)

- MinIO: buckets `bronze`, `silver`, `gold` y `governance` creados y accesibles.
- Ingesta: objeto de prueba cargado en `bronze/users/2026-07-17/smoke.csv`.
- Spark: Worker registrado en el Master con `8` cores y `8 GiB`; SparkPi
  distribuido completado con `exitCode 0` y ejecutores en `master2`.
- Airflow: `governance_bronze_validate` completó exitosamente las tareas
  `check_file_exists`, `run_quality_checks`, `assert_success` y `save_result`
  para la partición de prueba.
- Causa del retraso Airflow: el worker Celery tenía una conexión Redis
  reiniciada; se reinició solo `airflow_worker` y la ejecución encolada terminó
  correctamente. No se modificaron datos ni la base de metadatos.
- Limitación vigente: la imagen Spark oficial no trae soporte S3A configurado;
  todavía no se declara completada la transformación Bronze → Silver ni el
  flujo completo entre capas.
- Rollback: redeploy del manifiesto Spark anterior y `docker service update
  --force airflow_airflow_worker`; no se eliminaron volúmenes, buckets ni
  secretos.

### Incremento P2-R1 — promoción mínima de capas (2026-07-17)

- Se agregó el DAG `medallion_users_promote`.
- Lee un CSV de `bronze/users/<date>/`, normaliza columnas y elimina duplicados.
- Publica `silver/users/<date>/users.csv` y
  `gold/users/<date>/summary.csv`.
- La implementación usa boto3/pandas disponibles en Airflow; no requiere
  modificar la imagen Spark ni introducir soporte S3A prematuramente.
- Runtime: `medallion_users_promote` completó exitosamente en Airflow.
- Causa del fallo inicial: el DAG estaba presente en `master1`, pero faltaba en
  `/srv/fastdata/airflow/dags` de `master2`, que es la ruta montada por Celery.
- Corrección: sincronización del DAG en `master2`; no se modificaron imágenes,
  servicios stateful ni credenciales.
- Evidencia: `silver/users/2026-07-17/users.csv` y
  `gold/users/2026-07-17/summary.csv` creados en MinIO.
- El DAG ahora registra cada promoción en la tabla
  `lab_medallion_audit` de la base Airflow.
- Evidencia runtime: ejecución `manual__2026-07-17T04:12:22+00:00` con tareas
  `promote` y `audit` exitosas; auditoría registrada para `users`, partición
  `2026-07-17`, con una fila procesada.
- Pendiente: ejecutar validación Silver, completar la variante distribuida con
  Spark cuando la imagen tenga soporte S3A y registrar lineage.

## P2-R2 — OpenSearch y observabilidad

- [ ] Crear plantilla para `docker-logs-*`.
- [ ] Enriquecer logs con servicio, stack, nodo y dataset.
- [ ] Definir política ISM de laboratorio.
- [ ] Crear dashboards de `master1` y `master2`.
- [ ] Crear dashboard de servicios stateful.
- [ ] Crear dashboard GPU.
- [ ] Crear dashboard de Airflow y Spark.
- [ ] Crear índices de trazas RAG y agentes solamente cuando las aplicaciones los produzcan.
- [ ] Crear alertas útiles en Grafana sin duplicar Alertmanager.
- [ ] Enlazar alertas importantes con runbooks.

## P2-R3 — Qdrant, RAG y GraphRAG

- [ ] Definir convenciones de nombres de colecciones.
- [ ] Versionar modelo de embeddings y dimensión.
- [ ] Crear laboratorio RAG base.
- [ ] Crear laboratorio GraphRAG con relaciones manejadas por la aplicación.
- [ ] Comparar recuperación vectorial, híbrida y con contexto de grafo.
- [ ] Registrar métricas de calidad, latencia y consumo.
- [ ] Crear dataset de evaluación.
- [ ] Integrar resultados con RAG API, Agent y JupyterHub.
- [ ] Documentar cuándo usar Qdrant, pgvector u OpenSearch.

## P2-R4 — IA local

- [ ] Crear manifiesto de modelos Ollama.
- [ ] Registrar versión, cuantización, contexto, VRAM y propósito.
- [ ] Ejecutar benchmark reproducible en la RTX 2080 Ti.
- [ ] Seleccionar modelos por caso de uso.
- [ ] Integrar Open WebUI, RAG API y Agent.
- [ ] Mantener estrategia local-first.
- [ ] Implementar fallback cloud solamente si se aprueba un caso de uso.
- [ ] Medir calidad, latencia, VRAM y RAM.
- [ ] Evitar multiagentes hasta demostrar un beneficio concreto.

## P2-R5 — Git, CI/CD y control de drift

- [ ] Crear `docs/architecture/STATE.md` como estado actual verificable.
- [ ] Normalizar ADR duplicados y documentación histórica.
- [ ] Crear catálogo canónico de servicios.
- [ ] Crear mapas de puertos, volúmenes, placement y redes.
- [ ] Automatizar comparación Git/runtime.
- [ ] Validar YAML, Compose y scripts.
- [ ] Validar healthchecks, secrets, redes, placement y recursos.
- [ ] Sustituir imágenes con tag `latest` por versiones o digest.
- [ ] Crear smoke tests reutilizables.
- [ ] Generar siempre evidencia `.txt` en `~/lab-reports/`.

---

# 8. Orden de ejecución

1. P1-R6 — seguridad de red: cerrada con riesgo residual controlado.
2. P1-R7 — recuperar RAG API y estabilizar solo lo necesario.
3. Ejecutar un flujo mínimo Spark/MinIO/Airflow y validarlo de extremo a extremo.
4. Consolidar logging y observabilidad de los servicios usados.
5. P1-R8 — PostgreSQL/OpenSearch compartidos y Qdrant en `master2`.
6. Construir laboratorios Qdrant/RAG/GraphRAG.
7. Optimizar modelos y flujos de IA local.
8. Completar CI/CD, documentación y control de drift.

No se iniciará una fase stateful destructiva sin validar primero la configuración objetivo y solicitar autorización explícita para retirar los servicios antiguos.

---

# 9. Criterios generales de aceptación

Una tarea podrá marcarse `[x]` solamente cuando:

- El cambio esté representado en GitHub.
- Exista PR revisado y fusionado cuando corresponda.
- El stack haya convergido en Docker Swarm.
- Placement, réplicas y healthchecks sean correctos.
- Exista prueba funcional del servicio.
- CPU, RAM, disco y GPU no presenten una regresión injustificada.
- Se genere evidencia sin secretos en un archivo `.txt`.
- La evidencia se almacene en Drive dentro de la carpeta de reportes correspondiente.
- La propuesta y los documentos de arquitectura queden actualizados.

Los estados permitidos serán:

```text
[ ] Pendiente
[~] En ejecución o validación
[x] Finalizado y verificado
[!] Bloqueado o descartado, con explicación
```

---

# 10. Formato de evidencia

Cada intervención deberá producir un archivo:

```text
~/lab-reports/<fase>-<nodo>-YYYYMMDD_HHMMSS.txt
```

Contenido mínimo:

```text
FASE=
NODO=
FECHA=
OBJETIVO=
COMANDOS_EJECUTADOS=
SALIDA_RELEVANTE=
VALIDACIONES=
ERRORES=
ESTADO_FINAL=
COMMIT_O_PR=
```

El reporte no debe contener contraseñas, tokens, claves privadas, contenido de Docker Secrets ni variables sensibles.

---

# 11. Veredicto vigente

El laboratorio ya superó la instalación básica. La prioridad inmediata no es
incorporar más herramientas ni ejecutar una gran refactorización stateful, sino
recuperar la ruta funcional mínima y luego evolucionarla para que:

- `master1` coordine y publique servicios.
- `master2` concentre datos, procesamiento y GPU.
- PostgreSQL y OpenSearch sean servicios compartidos y bien separados lógicamente.
- Qdrant soporte los laboratorios vectoriales y GraphRAG.
- Spark sea el motor central de transformación de datos.
- Todos los servicios puedan permanecer disponibles para los dos usuarios con límites razonables.
- Authentik y la complejidad SSO queden descartados.
- Cada mejora sea reproducible, verificable y documentada.

La actividad operativa vigente es **P1-R7 — Recuperación funcional,
healthchecks y recursos**. P1-R6 quedó finalizada con política IPv4 exacta,
producto funcional y riesgo residual documentado. La parte operativa de P1-R7
quedó verificada; permanece pendiente únicamente el cierre administrativo
mediante commit/PR. P1-R8 y las fases P2 continúan deliberadamente diferidas.

---

# 12. Control de aprobación

- [x] Objetivo y alcance revisados.
- [x] Decisiones de arquitectura revisadas.
- [x] Distribución de servicios y recursos revisada.
- [x] Topología PostgreSQL, OpenSearch, Qdrant y Spark revisada.
- [x] Fases, criterios de aceptación y evidencia revisados.
- [x] Propuesta aprobada por el usuario el 2026-07-16.

La aprobación autoriza el uso de esta propuesta como plan documental vigente. No autoriza por sí sola eliminaciones, reinicios ni cambios destructivos; cada ejecución seguirá sus controles específicos.
