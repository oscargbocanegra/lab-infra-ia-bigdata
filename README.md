# lab-infra-ia-bigdata

Infra reproducible en Docker Swarm para IA/Big Data.

## Objetivo
Infra reproducible en Docker Swarm para IA/Big Data, con seguridad por defecto, observabilidad y despliegue por fases.

## Orden de despliegue (Fase 4)
1) stacks/core/00-traefik
2) stacks/core/01-portainer
3) stacks/data/10-postgres
4) stacks/automation/02-n8n
5) stacks/data/11-opensearch
6) stacks/ai-ml/20-jupyter
7) stacks/ai-ml/21-ollama
8) stacks/data/98-spark
9) stacks/automation/99-airflow

## Estado actual (OK / Falta)
### OK
- Swarm activo (master1 manager, master2 worker)
- Redes overlay: public, internal
- Persistencia master2: /srv/fastdata y /srv/datalake montados y persistentes

### Falta
- Crear stacks YAML (Postgres/n8n/OpenSearch/Jupyter/Ollama/Spark/Airflow)
- Crear/registrar Docker secrets por stack
- Ejecutar despliegue por `docker stack deploy` en master1
- Runbooks: backup/restore + healthcheck

## Uso rápido
- Validaciones: scripts/verify/
- Despliegue: docker stack deploy -c stacks/<...>/stack.yml <stackname>

