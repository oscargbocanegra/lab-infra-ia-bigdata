# ADR-004: OpenSearch security plugin deshabilitado

**Fecha**: 2026-01  
**Estado**: Aceptado (revisable si el lab se abre a internet)

---

## Contexto

OpenSearch incluye un plugin de seguridad que ofrece:
- TLS entre nodos del clúster
- Autenticación básica interna (users/roles en una DB propia)
- RBAC a nivel de índice
- Auditoría

En un ambiente de 1 nodo (single-node), la mayoría de estas features son overhead sin valor real.

---

## Decisión

**`DISABLE_SECURITY_PLUGIN=true`** en el stack de OpenSearch.

---

## Motivos

1. **Sin valor real en single-node**: TLS entre nodos es irrelevante con 1 nodo. RBAC de índices es overhead de configuración para un lab de aprendizaje.

2. **Complejidad alta**: El plugin requiere generar certificados internos para la API de admin, configurar `opensearch.yml` con los paths de certs, generar el hash de passwords con una herramienta específica... Todo esto por encima de Traefik (que ya tiene TLS) y BasicAuth (que ya tiene auth).

3. **Defensa en profundidad suficiente para lab**:
   - Capa 1: LAN-only (no expuesto a internet)
   - Capa 2: Traefik `lan-whitelist` (solo 192.168.80.0/24)
   - Capa 3: BasicAuth en Traefik para el endpoint externo
   - Capa 4: Red overlay `internal` para acceso service-to-service (sin autenticación de red pero sin exposición LAN)

4. **Consistencia con la filosofía del lab**: Reducir fricción de setup para maximizar tiempo de aprendizaje.

---

## Riesgo aceptado

- Si alguien en la LAN tiene acceso directo a master1:9200 (bypaseando Traefik), tiene acceso sin autenticación a OpenSearch.
- Mitigación: acceso directo requiere estar en LAN + conocer el puerto + Traefik es el único endpoint publicado.

---

## Cuando revisar esta decisión

- Si el lab se expone a una red corporativa más amplia
- Si se agregan índices con datos sensibles reales
- Si se conecta OpenSearch a un pipeline de producción
