# Imagen single-user de JupyterHub

Este directorio contiene únicamente el contexto de construcción de la imagen:

    giovannotti/lab-jupyter

No contiene ni despliega un stack JupyterLab independiente.

## Componentes

- `Dockerfile`
- `entrypoint.sh`
- `init-kernels.sh`

## Uso

JupyterHub crea dinámicamente los servicios:

    jupyterhub-user-ogiovanni
    jupyterhub-user-odavid

La persistencia canónica se encuentra en:

    /srv/fastdata/jupyterhub/users/<username>

La definición del antiguo stack standalone `jupyter` fue retirada.
