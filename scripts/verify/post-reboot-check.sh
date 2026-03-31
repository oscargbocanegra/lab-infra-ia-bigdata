#!/usr/bin/env bash
# =============================================================================
# post-reboot-check.sh — Verificación de salud del cluster tras un reboot
# =============================================================================
# Uso:
#   ssh ogiovanni@192.168.80.100 "bash ~/lab-infra-ia-bigdata/scripts/verify/post-reboot-check.sh"
#
# Qué verifica:
#   1. Ambos nodos Swarm activos (master1 + master2)
#   2. Todos los servicios en la réplica esperada (N/N)
#   3. Servicios críticos con health check propio
#   4. Conectividad interna: postgres, minio, redis, opensearch, ollama
#   5. Endpoints HTTPS accesibles vía Traefik (desde master1 LAN)
#
# Salida:
#   ✅ PASS / ❌ FAIL por cada check
#   Exit code 0 si todo pasa, 1 si hay algún FAIL
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
NC='\033[0m'

PASS=0
FAIL=0

pass() { echo -e "${GREEN}✅ PASS${NC} — $1"; ((PASS++)); }
fail() { echo -e "${RED}❌ FAIL${NC} — $1"; ((FAIL++)); }
warn() { echo -e "${YELLOW}⚠️  WARN${NC} — $1"; }
section() { echo -e "\n${BLUE}══ $1 ══${NC}"; }

# =============================================================================
# 1. Nodos Swarm
# =============================================================================
section "Nodos Swarm"

NODES=$(docker node ls --format "{{.Hostname}} {{.Status}} {{.Availability}}" 2>/dev/null || echo "")

check_node() {
  local hostname="$1"
  local line
  line=$(echo "$NODES" | grep "$hostname" || true)
  if echo "$line" | grep -q "Ready.*Active"; then
    pass "Nodo $hostname: Ready + Active"
  else
    fail "Nodo $hostname: no está Ready/Active → '$line'"
  fi
}

check_node "master1"
check_node "master2"

# =============================================================================
# 2. Servicios Swarm (réplicas esperadas)
# =============================================================================
section "Servicios Docker Swarm"

# Formato: "nombre_servicio réplicas_esperadas"
# airflow_airflow_init va con 0 replicas (job único ya ejecutado)
EXPECTED_SERVICES=(
  "traefik_traefik:1"
  "portainer_portainer:1"
  "portainer_agent:2"
  "postgres_postgres:1"
  "n8n_n8n:1"
  "jupyter_jupyter_ogiovanni:1"
  "jupyter_jupyter_odavid:1"
  "ollama_ollama:1"
  "opensearch_opensearch:1"
  "opensearch_dashboards:1"
  "minio_minio:1"
  "spark_spark_master:1"
  "spark_spark_worker:1"
  "spark_spark_history:1"
  "airflow_redis:1"
  "airflow_airflow_webserver:1"
  "airflow_airflow_scheduler:1"
  "airflow_airflow_worker:1"
  "airflow_airflow_flower:1"
)

for svc_spec in "${EXPECTED_SERVICES[@]}"; do
  svc_name="${svc_spec%%:*}"
  expected="${svc_spec##*:}"

  replicas=$(docker service ls --filter "name=${svc_name}" --format "{{.Replicas}}" 2>/dev/null || echo "")

  if [ -z "$replicas" ]; then
    fail "Servicio ${svc_name}: NO ENCONTRADO"
    continue
  fi

  running="${replicas%%/*}"
  total="${replicas##*/}"

  if [ "$running" = "$expected" ] && [ "$total" = "$expected" ]; then
    pass "Servicio ${svc_name}: ${replicas}"
  else
    fail "Servicio ${svc_name}: ${replicas} (esperado ${expected}/${expected})"
  fi
done

# =============================================================================
# 3. Conectividad interna
# =============================================================================
section "Conectividad interna (desde manager)"

check_tcp() {
  local label="$1"
  local host="$2"
  local port="$3"
  if docker run --rm --network internal alpine sh -c "nc -z -w3 ${host} ${port}" 2>/dev/null; then
    pass "${label}: ${host}:${port} accesible"
  else
    fail "${label}: ${host}:${port} NO responde"
  fi
}

check_http() {
  local label="$1"
  local url="$2"
  local expected_code="${3:-200}"
  local code
  code=$(docker run --rm --network internal alpine sh -c \
    "wget -q -O /dev/null -S '${url}' 2>&1 | grep 'HTTP/' | awk '{print \$2}' | head -1" 2>/dev/null || echo "000")
  if [ "$code" = "$expected_code" ] || [ "$code" = "200" ] || [ "$code" = "301" ] || [ "$code" = "302" ] || [ "$code" = "401" ]; then
    pass "${label}: ${url} → HTTP ${code}"
  else
    fail "${label}: ${url} → HTTP ${code} (esperado ${expected_code})"
  fi
}

check_tcp "PostgreSQL" "postgres_postgres" "5432"
check_tcp "Redis (Celery)" "airflow_redis" "6379"
check_tcp "MinIO S3 API" "minio_minio" "9000"
check_tcp "OpenSearch" "opensearch_opensearch" "9200"
check_tcp "Ollama API" "ollama_ollama" "11434"
check_tcp "Spark Master" "spark_spark_master" "7077"

# =============================================================================
# 4. Endpoints HTTPS (via Traefik, desde la LAN)
# =============================================================================
section "Endpoints HTTPS via Traefik (LAN)"

check_https() {
  local label="$1"
  local url="$2"
  local code
  code=$(curl -sk -o /dev/null -w "%{http_code}" "${url}" 2>/dev/null || echo "000")
  if [[ "$code" =~ ^(200|301|302|401|403)$ ]]; then
    pass "${label}: ${url} → HTTP ${code}"
  else
    fail "${label}: ${url} → HTTP ${code}"
  fi
}

check_https "Traefik Dashboard"         "https://traefik.sexydad/dashboard/"
check_https "Portainer"                 "https://portainer.sexydad"
check_https "n8n"                       "https://n8n.sexydad"
check_https "Airflow"                   "https://airflow.sexydad/health"
check_https "Airflow Flower"            "https://airflow-flower.sexydad"
check_https "MinIO Console"             "https://minio.sexydad"
check_https "MinIO S3 API"              "https://minio-api.sexydad/minio/health/live"
check_https "OpenSearch API"            "https://opensearch.sexydad/_cluster/health"
check_https "OpenSearch Dashboards"     "https://dashboards.sexydad"
check_https "Ollama API"                "https://ollama.sexydad/api/tags"
check_https "Jupyter ogiovanni"         "https://jupyter-ogiovanni.sexydad"
check_https "Jupyter odavid"            "https://jupyter-odavid.sexydad"
check_https "Spark Master UI"           "https://spark-master.sexydad"
check_https "Spark History"             "https://spark-history.sexydad"

# =============================================================================
# 5. Resumen
# =============================================================================
section "Resumen"

TOTAL=$((PASS + FAIL))
echo ""
echo -e "  Total checks : ${TOTAL}"
echo -e "  ${GREEN}Passed${NC}       : ${PASS}"
echo -e "  ${RED}Failed${NC}       : ${FAIL}"
echo ""

if [ $FAIL -eq 0 ]; then
  echo -e "${GREEN}🎉 Cluster 100% operativo post-reboot${NC}"
  exit 0
else
  echo -e "${RED}⚠️  Hay ${FAIL} checks fallidos — revisar arriba${NC}"
  echo ""
  echo "Tips de diagnóstico:"
  echo "  docker service ls                           # ver estado de todos los servicios"
  echo "  docker service ps <nombre_servicio>         # ver historial de tareas"
  echo "  docker service logs <nombre_servicio> -f    # ver logs en tiempo real"
  exit 1
fi
