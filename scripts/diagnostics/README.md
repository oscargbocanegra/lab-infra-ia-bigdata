# Diagnóstico del laboratorio

Componentes:

- `lab-report.sh`: inventario no destructivo del host.
- `lab-power-marker.sh`: identifica apagados limpios o inesperados.
- `analyze-reboot.sh`: analiza el arranque anterior.
- `install-reboot-diagnostics.sh`: instalación idempotente.
- `systemd/`: servicio de marcador, servicio de análisis y timer.

Los reportes automáticos se guardan en `/var/log/lab-health/reboot`.

La instalación debe realizarse en cada nodo desde una copia sincronizada del repositorio:

    sudo ./scripts/diagnostics/install-reboot-diagnostics.sh

Runbook: `docs/runbooks/REBOOT_DIAGNOSTICS.md`
