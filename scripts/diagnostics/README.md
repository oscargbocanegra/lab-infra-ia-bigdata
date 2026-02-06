# Scripts de Diagnóstico

## analyze-reboot.sh

Script de análisis post-reinicio para detectar la causa de reinicios inesperados en master1.

### Uso

```bash
# Ejecutar después de un reinicio
./scripts/diagnostics/analyze-reboot.sh
```

### Qué analiza

1. **Información del sistema** - uptime y fecha del último boot
2. **Historial de reinicios** - últimos 10 reinicios registrados
3. **Eventos de kernel** - OOM (Out of Memory), Kernel Panic, errores críticos
4. **Logs de Docker** - errores fatales en Docker daemon
5. **Recursos actuales** - memoria, disco, CPU load
6. **Estado Docker Swarm** - nodos y servicios
7. **Logs del sistema** - errores críticos en syslog
8. **Hardware** - errores de hardware, temperatura
9. **Sensores** - temperatura actual (si lm-sensors instalado)
10. **Resumen automático** - hallazgos detectados

### Salida

- Reporte en pantalla y guardado en `/tmp/reboot-analysis-<timestamp>.txt`
- Copia permanente en `/tmp/reboot-analysis-latest.txt`

### Causas comunes detectadas

- ⚠️ **OOM (Out of Memory)** - Memoria RAM agotada
- ⚠️ **Kernel Panic** - Error crítico del kernel
- ⚠️ **Error de hardware** - Problemas con CPU, RAM, disco
- ⚠️ **Error fatal Docker** - Docker daemon crashed

### Recomendaciones post-análisis

Si detecta **OOM**:
- Revisar consumo de memoria: `docker stats`
- Limitar recursos de contenedores en los stacks
- Considerar añadir más RAM o swap

Si detecta **Kernel Panic**:
- Revisar hardware (memtest86+)
- Actualizar kernel: `apt update && apt upgrade`

Si detecta **Hardware error**:
- Revisar logs completos: `journalctl -b -1 | grep -i error`
- Verificar SMART del disco: `smartctl -a /dev/sda`
- Revisar temperatura: `sensors`

### Automatización

Para ejecutar automáticamente después de cada boot, crear systemd service:

```bash
sudo tee /etc/systemd/system/analyze-reboot.service << 'EOF'
[Unit]
Description=Analyze reboot causes
After=docker.service

[Service]
Type=oneshot
ExecStart=/path/to/lab-infra-ia-bigdata/scripts/diagnostics/analyze-reboot.sh
User=ogiovanni

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl enable analyze-reboot.service
```
