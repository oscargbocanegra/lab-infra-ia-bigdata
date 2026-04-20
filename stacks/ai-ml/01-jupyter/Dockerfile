# =============================================================================
# lab-jupyter — Custom JupyterLab image for lab-infra-ia-bigdata
# =============================================================================
# Base: jupyter/datascience-notebook:python-3.11
#
# Bakes in all server extensions and data-science pip packages so the
# container starts in ~15s instead of 3+ min (no runtime pip install).
#
# Runtime scripts (entrypoint.sh, init-kernels.sh) still run at container
# start to: write IPython startup files with JARVIS_MODEL env var,
# enable server extensions in the user home, and create venvs on NVMe.
#
# Build + push is handled by GitHub Actions deploy.yml.
# Tag convention:
#   giovannotti/lab-jupyter:latest      → newest build
#   giovannotti/lab-jupyter:sha-<hash>  → exact commit traceability
# =============================================================================

FROM jupyter/datascience-notebook:python-3.11

# ── Install as root to write to system Python ────────────────────────────────
USER root

# ── Server extensions (baked in — no more runtime pip install) ───────────────
# Previously installed in init-kernels.sh on every boot (~2-3 min).
# Now installed once at image build time.
RUN pip install --no-cache-dir \
    "jupyterlab>=4.2.0,<4.3.0" \
    "jupyterlab-server>=2.27.0" \
    "jupyter-lsp>=2.2.0,<3.0" \
    "jupyterlab-lsp>=5.0.0,<6.0" \
    "jedi-language-server>=0.41.0" \
    "jupyter-ai>=2.20.0,<3.0" \
    "langchain-community>=0.3.0,<0.4.0" \
    "langchain-ollama>=0.2.0,<1.0" \
    "itables" \
    "ydata-profiling>=4.6.0" \
    "ipywidgets"

# ── Switch back to notebook user ─────────────────────────────────────────────
USER ${NB_UID}
