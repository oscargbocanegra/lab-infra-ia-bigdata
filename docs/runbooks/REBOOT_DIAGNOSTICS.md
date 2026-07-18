# Reboot Diagnostics

## Objetivo

Registrar si el apagado anterior fue limpio o inesperado y generar evidencia del arranque anterior en `master1` y `master2`.

## Componentes

- `lab-power-marker.service`
- `lab-report-boot.service`
- `lab-report-boot.timer`
- `lab-reboot-analysis.service`
- `lab-reboot-analysis.timer`

## Persistencia

- `/var/lib/lab-health`
- `/var/log/lab-health/reboot`

No se utilizan `/tmp`, volúmenes Docker ni almacenamiento stateful de servicios.

## Instalación

Ejecutar en cada nodo:

    cd ~/lab-infra-ia-bigdata
    sudo ./scripts/diagnostics/install-reboot-diagnostics.sh

## Verificación

    systemctl status lab-power-marker.service --no-pager
    systemctl status lab-report-boot.timer --no-pager
    systemctl status lab-reboot-analysis.timer --no-pager
    systemctl list-timers lab-report-boot.timer lab-reboot-analysis.timer --no-pager
    sudo systemctl start lab-reboot-analysis.service
    sudo ls -lah /var/log/lab-health/reboot

## Criterios de éxito

- marcador activo;
- reporte diferido activo;
- timer activo;
- análisis manual exitoso;
- reporte con `REBOOT_ANALYSIS_STATUS=COMPLETE`;
- sin unidades systemd fallidas nuevas.

## Rollback seguro

    sudo systemctl disable --now lab-report-boot.timer
    sudo systemctl disable --now lab-reboot-analysis.timer
    sudo systemctl disable --now lab-power-marker.service

Los reportes y estados se conservan para investigación. El rollback del código se realiza mediante `git revert`.

## Migración desde la unidad legacy

El instalador deshabilita y preserva automáticamente:

- `/etc/systemd/system/analyze-reboot.service`
- `/opt/node_maintenance/analyze_reboot.sh`

Los archivos se mueven a:

```text
/var/lib/lab-health/legacy-backup/<timestamp>
```

No se eliminan evidencias ni archivos legacy.
