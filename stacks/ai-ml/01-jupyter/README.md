# Imagen single-user de JupyterHub

Este directorio contiene únicamente el contexto de construcción de la imagen:

    giovannotti/lab-jupyter

No contiene ni despliega un stack JupyterLab independiente.

## Componentes

- `Dockerfile`
- `entrypoint.sh`
- `init-kernels.sh`
- `pyspark==3.5.3` y OpenJDK 17 para ejecutar ejercicios contra el Spark
  Master del laboratorio desde sesiones single-user.

## Uso

JupyterHub crea dinámicamente los servicios:

    jupyterhub-user-ogiovanni
    jupyterhub-user-odavid

La sesión usa `spark://spark-master-internal:7077` como URL del Master.

La persistencia canónica se encuentra en:

    /srv/fastdata/jupyterhub/users/<username>

La definición del antiguo stack standalone `jupyter` fue retirada.
