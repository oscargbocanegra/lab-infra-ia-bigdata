# ADR-015: Retirada de JupyterLab standalone

- Estado: Aceptado
- Fecha: 2026-07-11

## Contexto

JupyterHub alcanzó paridad funcional para `ogiovanni` y `odavid`,
incluyendo persistencia, kernels, JARVIS, Ollama, GPU y MinIO.

Mantener dos JupyterLab standalone duplicaba servicios, routers,
BasicAuth, configs, consumo de recursos y procedimientos operativos.

## Decisión

JupyterHub será la única plataforma Jupyter activa.

Se retiran:

- stack `jupyter`;
- servicios `jupyter_jupyter_*`;
- routers y middlewares standalone;
- secret `jupyter_basicauth_v2`;
- configs históricas;
- definición `stacks/ai-ml/01-jupyter/stack.yml`.

El directorio `stacks/ai-ml/01-jupyter` permanece como contexto de
construcción de la imagen single-user:

    giovannotti/lab-jupyter

La persistencia canónica queda en:

    /srv/fastdata/jupyterhub/users/<username>

## Consecuencias positivas

- menor superficie de exposición;
- menor consumo de CPU y RAM;
- una única autenticación;
- una única entrada Jupyter;
- IaC y operación más simples;
- menor riesgo de drift.

## Riesgos

El rollback ya no consiste en escalar los servicios standalone. Restaurar
el stack legacy exige recuperar su definición desde Git.

## Rollback

1. Revertir el commit de retirada.
2. Recuperar `stack.yml` desde el historial Git.
3. Recrear el secret BasicAuth únicamente si fuera necesario.
4. Redesplegar Traefik.
5. Redesplegar temporalmente el stack legacy.
6. No modificar las rutas canónicas de JupyterHub.
