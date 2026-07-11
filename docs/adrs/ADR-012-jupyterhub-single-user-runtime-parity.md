# ADR-012: Paridad del runtime single-user de JupyterHub

- Estado: Aceptado
- Fecha: 2026-07-11

## Contexto

JupyterHub utilizaba la imagen single-user existente, pero no
ejecutaba el bootstrap de los JupyterLab legacy. Por ello no se
exponían JARVIS, los kernels personalizados ni las credenciales
MinIO.

Además, los kernels persistentes almacenados en el home del
usuario quedaban ocultos cuando `disable_user_config` estaba
habilitado.

## Decisión

1. Mantener JupyterHub en `master1`.
2. Mantener los single-users en `master2`.
3. Usar `/srv/fastdata/jupyterhub/users/<username>` como
   almacenamiento canónico.
4. Entregar el bootstrap mediante Docker Swarm Configs.
5. Asociar MinIO mediante Docker Swarm Secrets.
6. Mantener `c.Spawner.disable_user_config = False`.
7. Exponer los kernels `llm`, `ia` y `bigdata` desde `.local`.
8. Mantener temporalmente los servicios legacy como rollback.
9. Retirar el runtime legacy en un cambio posterior.

## Consecuencias positivas

- paridad funcional para ambos usuarios;
- configuración reproducible desde Git;
- JARVIS y Ollama disponibles;
- kernels y entornos persistentes;
- almacenamiento separado por usuario;
- rollback operativo disponible.

## Riesgos aceptados

La configuración del home del usuario está habilitada. El riesgo
es aceptable porque el laboratorio tiene dos usuarios confiables
y no es una plataforma multi-tenant pública.

El acceso al Docker Socket del Hub continúa bajo el riesgo y las
medidas documentadas en ADR-011.

## Rollback

1. Revertir los commits de paridad.
2. Redesplegar el stack `jupyterhub` desde `master1`.
3. Recrear los servicios single-user.
4. Usar temporalmente los JupyterLab legacy.
5. No eliminar datos, configs, secrets ni backups.

## Evidencia de aceptación

- Hub saludable;
- ambos usuarios en `1/1`;
- kernels LLM, IA y BigData visibles;
- `/jarvis` y `%%JARVIS` funcionales;
- Ollama y GPU operativos;
- secretos MinIO presentes;
- persistencia validada.
