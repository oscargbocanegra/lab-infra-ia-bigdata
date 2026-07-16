# Runbook histórico: JupyterLab standalone

> **Estado:** retirado el 2026-07-11 mediante ADR-015.
> No ejecutar procedimientos de este documento para desplegar JupyterLab standalone.

## Plataforma canónica

La plataforma Jupyter activa es JupyterHub:

- Hub en `master1`.
- Servidores single-user dinámicos en `master2`.
- Persistencia en `/srv/fastdata/jupyterhub/users/<username>`.
- Runbook operativo: [JUPYTERHUB_SWARM.md](JUPYTERHUB_SWARM.md).

## Recuperación excepcional

Restaurar JupyterLab standalone solo mediante el historial Git, una ADR
temporal y validación de impacto, seguridad y rollback.
