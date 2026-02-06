#!/usr/bin/env bash
set -euo pipefail

# analyze-reboot.sh
# Analiza logs históricos para detectar causa de reinicio en master1

REPORT_FILE="/tmp/reboot-analysis-$(date +%Y%m%d-%H%M%S).txt"
LAST_BOOT=$(who -b | awk '{print $3, $4}')

echo "========================================" | tee "$REPORT_FILE"
echo "ANÁLISIS POST-REINICIO - master1" | tee -a "$REPORT_FILE"
echo "========================================" | tee -a "$REPORT_FILE"
echo "Fecha análisis: $(date)" | tee -a "$REPORT_FILE"
echo "Último boot: $LAST_BOOT" | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

# 1. INFORMACIÓN DEL SISTEMA
echo "=== 1. INFORMACIÓN DEL SISTEMA ===" | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"
uptime | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

# 2. CAUSA DEL ÚLTIMO REINICIO
echo "=== 2. CAUSA DEL ÚLTIMO REINICIO ===" | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

if command -v last &> /dev/null; then
    echo "--- Últimos reinicios ---" | tee -a "$REPORT_FILE"
    last reboot | head -10 | tee -a "$REPORT_FILE"
    echo "" | tee -a "$REPORT_FILE"
fi

if command -v journalctl &> /dev/null; then
    echo "--- Logs del último boot ---" | tee -a "$REPORT_FILE"
    journalctl -b -1 --no-pager | tail -100 | tee -a "$REPORT_FILE"
    echo "" | tee -a "$REPORT_FILE"
    
    echo "--- Errores críticos boot anterior ---" | tee -a "$REPORT_FILE"
    journalctl -b -1 -p err --no-pager | tail -50 | tee -a "$REPORT_FILE"
    echo "" | tee -a "$REPORT_FILE"
fi

# 3. EVENTOS DE KERNEL (OOM, Panic, etc)
echo "=== 3. EVENTOS CRÍTICOS DE KERNEL ===" | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

if [ -f /var/log/kern.log ]; then
    echo "--- Out of Memory (OOM) ---" | tee -a "$REPORT_FILE"
    grep -i "out of memory\|oom-kill\|killed process" /var/log/kern.log | tail -20 | tee -a "$REPORT_FILE"
    echo "" | tee -a "$REPORT_FILE"
    
    echo "--- Kernel Panic ---" | tee -a "$REPORT_FILE"
    grep -i "panic\|oops\|bug:" /var/log/kern.log | tail -20 | tee -a "$REPORT_FILE"
    echo "" | tee -a "$REPORT_FILE"
fi

if command -v journalctl &> /dev/null; then
    echo "--- OOM desde journalctl ---" | tee -a "$REPORT_FILE"
    journalctl -b -1 --no-pager | grep -i "out of memory\|oom" | tail -20 | tee -a "$REPORT_FILE"
    echo "" | tee -a "$REPORT_FILE"
fi

# 4. LOGS DE DOCKER
echo "=== 4. EVENTOS DE DOCKER ===" | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

if command -v journalctl &> /dev/null; then
    echo "--- Errores Docker boot anterior ---" | tee -a "$REPORT_FILE"
    journalctl -b -1 -u docker --no-pager | grep -i "error\|fatal\|failed" | tail -30 | tee -a "$REPORT_FILE"
    echo "" | tee -a "$REPORT_FILE"
fi

# 5. ESTADO ACTUAL DE RECURSOS
echo "=== 5. RECURSOS ACTUALES ===" | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

echo "--- Memoria ---" | tee -a "$REPORT_FILE"
free -h | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

echo "--- Disco ---" | tee -a "$REPORT_FILE"
df -h | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

echo "--- Load Average ---" | tee -a "$REPORT_FILE"
cat /proc/loadavg | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

# 6. ESTADO DE DOCKER SWARM
echo "=== 6. ESTADO DOCKER SWARM ===" | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

if command -v docker &> /dev/null; then
    echo "--- Nodos del cluster ---" | tee -a "$REPORT_FILE"
    docker node ls 2>&1 | tee -a "$REPORT_FILE"
    echo "" | tee -a "$REPORT_FILE"
    
    echo "--- Servicios (estado) ---" | tee -a "$REPORT_FILE"
    docker service ls 2>&1 | tee -a "$REPORT_FILE"
    echo "" | tee -a "$REPORT_FILE"
    
    echo "--- Servicios con problemas ---" | tee -a "$REPORT_FILE"
    docker service ls --filter "mode=replicated" 2>&1 | awk '$4 !~ /^[0-9]+\/\1$/ && NR>1' | tee -a "$REPORT_FILE"
    echo "" | tee -a "$REPORT_FILE"
fi

# 7. LOGS DEL SISTEMA (SYSLOG)
echo "=== 7. EVENTOS SYSLOG CRÍTICOS ===" | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

if [ -f /var/log/syslog ]; then
    echo "--- Últimos errores críticos ---" | tee -a "$REPORT_FILE"
    grep -i "error\|critical\|emergency" /var/log/syslog | tail -30 | tee -a "$REPORT_FILE"
    echo "" | tee -a "$REPORT_FILE"
fi

# 8. VERIFICACIÓN DE HARDWARE
echo "=== 8. EVENTOS DE HARDWARE ===" | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

if command -v journalctl &> /dev/null; then
    echo "--- Errores de hardware ---" | tee -a "$REPORT_FILE"
    journalctl -b -1 --no-pager | grep -i "hardware error\|mce\|temperature\|thermal" | tail -20 | tee -a "$REPORT_FILE"
    echo "" | tee -a "$REPORT_FILE"
fi

# 9. TEMPERATURA Y SENSORES (si disponible)
echo "=== 9. SENSORES (actual) ===" | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

if command -v sensors &> /dev/null; then
    sensors 2>&1 | tee -a "$REPORT_FILE"
    echo "" | tee -a "$REPORT_FILE"
else
    echo "sensors no disponible (instalar: apt install lm-sensors)" | tee -a "$REPORT_FILE"
    echo "" | tee -a "$REPORT_FILE"
fi

# 10. RESUMEN Y RECOMENDACIONES
echo "=== 10. RESUMEN ===" | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

# Análisis automático
FINDINGS=""

if [ -f /var/log/kern.log ] && grep -qi "out of memory\|oom-kill" /var/log/kern.log; then
    FINDINGS="${FINDINGS}\n⚠️  OOM detectado - Memoria insuficiente"
fi

if command -v journalctl &> /dev/null && journalctl -b -1 --no-pager | grep -qi "panic"; then
    FINDINGS="${FINDINGS}\n⚠️  Kernel Panic detectado"
fi

if [ -f /var/log/kern.log ] && grep -qi "hardware error" /var/log/kern.log; then
    FINDINGS="${FINDINGS}\n⚠️  Error de hardware detectado"
fi

if command -v journalctl &> /dev/null && journalctl -b -1 -u docker --no-pager | grep -qi "fatal"; then
    FINDINGS="${FINDINGS}\n⚠️  Error fatal en Docker"
fi

if [ -n "$FINDINGS" ]; then
    echo "HALLAZGOS:" | tee -a "$REPORT_FILE"
    echo -e "$FINDINGS" | tee -a "$REPORT_FILE"
else
    echo "ℹ️  No se detectaron causas obvias. Revisar logs completos." | tee -a "$REPORT_FILE"
fi

echo "" | tee -a "$REPORT_FILE"
echo "========================================" | tee -a "$REPORT_FILE"
echo "Reporte guardado en: $REPORT_FILE" | tee -a "$REPORT_FILE"
echo "========================================" | tee -a "$REPORT_FILE"

# Copiar reporte a ubicación permanente
cp "$REPORT_FILE" "/tmp/reboot-analysis-latest.txt"
echo "Copia permanente: /tmp/reboot-analysis-latest.txt"
