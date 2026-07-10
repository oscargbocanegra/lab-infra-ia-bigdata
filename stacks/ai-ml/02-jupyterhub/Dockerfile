FROM python:3.11-slim-bookworm@sha256:f5cf0344c9886ff24d34797578d5d7dd6e8911ae0fe5962bb55d0f89603ec361

LABEL org.opencontainers.image.title="Lab JupyterHub"
LABEL org.opencontainers.image.description="JupyterHub control plane for Docker Swarm"
LABEL org.opencontainers.image.source="https://github.com/oscargbocanegra/lab-infra-ia-bigdata"

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1

RUN apt-get update \
    && apt-get install --yes --no-install-recommends \
        ca-certificates \
        curl \
        nodejs \
        npm \
        tini \
    && npm install --global configurable-http-proxy@4.6.3 \
    && npm cache clean --force \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /srv/jupyterhub

COPY requirements.txt /srv/jupyterhub/requirements.txt
COPY requirements.lock /srv/jupyterhub/requirements.lock

RUN python -m pip install --upgrade pip==26.1.2 \
    && python -m pip install --requirement /srv/jupyterhub/requirements.lock

COPY entrypoint.sh /usr/local/bin/jupyterhub-entrypoint
COPY jupyterhub_config.py /srv/jupyterhub/jupyterhub_config.py

RUN chmod 0755 /usr/local/bin/jupyterhub-entrypoint \
    && mkdir -p /srv/jupyterhub/data

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD curl --fail --silent --show-error http://127.0.0.1:8000/hub/health || exit 1

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/jupyterhub-entrypoint"]
CMD ["jupyterhub", "--config", "/srv/jupyterhub/jupyterhub_config.py"]
