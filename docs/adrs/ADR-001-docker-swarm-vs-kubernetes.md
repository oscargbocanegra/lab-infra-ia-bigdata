# ADR-001: Docker Swarm sobre Kubernetes

**Fecha**: 2025-12 (diseño inicial)  
**Estado**: Aceptado  
**Autores**: ogiovanni, odavid

---

## Contexto

El laboratorio tiene 2 nodos físicos con el objetivo de correr workloads de IA/Big Data. Se necesita un orquestador de containers para gestionar los servicios de forma declarativa y reproducible.

Las opciones evaluadas fueron:
1. **Docker Swarm** — orquestador nativo de Docker, simple
2. **Kubernetes (K8s)** — estándar de la industria, complejo
3. **K3s** — Kubernetes liviano para entornos edge/lab

---

## Decisión

**Se eligió Docker Swarm**.

---

## Motivos

1. **Complejidad operativa innecesaria**: K8s con 2 nodos requiere gestionar etcd, control-plane, CNI, CSI, Ingress Controller, CRDs... Swarm tiene todo esto integrado y funciona "out of the box".

2. **Overhead de recursos**: K8s consume ~2–4 GB de RAM solo para su control-plane (kube-apiserver, etcd, scheduler, controller-manager). Con 32 GB por nodo eso es dinero "quemado" en infraestructura del orquestador, no en workloads.

3. **Suficiente para el objetivo**: El lab es un ambiente de aprendizaje/experimentación, no producción con SLAs. Swarm provee: HA (cuando haya más nodos), service discovery, overlay networks, secrets, rolling updates — todo lo necesario.

4. **Docker Compose compatibility**: Los `stack.yml` de Swarm son supersets de `docker-compose.yml`. La curva de aprendizaje es mínima.

5. **GitOps simple**: `docker stack deploy -c stack.yml nombre` — no hay que aprender kubectl, Helm, kustomize, ni operators.

---

## Consecuencias

- ✅ Setup inicial en < 30 min (vs días para K8s)
- ✅ Operación simple (1 comando para desplegar/actualizar)
- ✅ Runbooks simples
- ⚠️ Si el lab crece a >5 nodos, evaluar migración a K3s
- ⚠️ Sin auto-scaling automático (no es necesario en lab)
- ⚠️ Sin rolling updates zero-downtime nativos para stateful services (workaround: drain + update)
