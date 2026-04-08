"""
conftest.py — RAG API test fixtures
====================================
Patches all external dependencies so tests run without a real cluster:
  - Qdrant client    → AsyncMock
  - Postgres session → AsyncMock
  - MinIO client     → MagicMock
  - Ollama HTTP      → httpx.MockTransport

The app is tested via ASGI transport (no real server needed).
All patches are applied at module level, before the app imports run,
to prevent connection attempts at startup (lifespan).
"""

import os
import sys
from unittest.mock import AsyncMock, MagicMock, patch

from httpx import ASGITransport, AsyncClient
import pytest
import pytest_asyncio

# ---------------------------------------------------------------------------
# Ensure the rag-api app is importable from tests/
# The app lives at: stacks/ai-ml/04-rag-api/
# We add it to sys.path so "from app.xxx import yyy" works.
# ---------------------------------------------------------------------------
RAG_API_PATH = os.path.join(
    os.path.dirname(__file__),
    "..",
    "..",
    "stacks",
    "ai-ml",
    "04-rag-api",
)
sys.path.insert(0, os.path.abspath(RAG_API_PATH))


# ---------------------------------------------------------------------------
# Qdrant mock — async client with collections and search
# ---------------------------------------------------------------------------
@pytest.fixture
def mock_qdrant_client():
    client = AsyncMock()
    # get_collections returns an object with .collections list
    collections_response = MagicMock()
    collections_response.collections = []
    client.get_collections.return_value = collections_response
    # search returns empty list by default (overridable per test)
    client.search.return_value = []
    # upsert returns success
    client.upsert.return_value = MagicMock(status="completed")
    return client


# ---------------------------------------------------------------------------
# Postgres session mock — async context manager
# ---------------------------------------------------------------------------
@pytest.fixture
def mock_pg_session():
    session = AsyncMock()
    session.execute.return_value = AsyncMock(scalar_one=MagicMock(return_value=1))
    session.commit.return_value = None

    # async context manager support: `async with get_session() as session:`
    session_cm = AsyncMock()
    session_cm.__aenter__.return_value = session
    session_cm.__aexit__.return_value = None
    return session_cm


# ---------------------------------------------------------------------------
# MinIO mock — sync client
# ---------------------------------------------------------------------------
@pytest.fixture
def mock_minio_client():
    client = MagicMock()
    client.put_object.return_value = None
    client.get_object.return_value = MagicMock(read=MagicMock(return_value=b""))
    return client


# ---------------------------------------------------------------------------
# Full app client — patches everything, returns httpx.AsyncClient
# Tests use this as: `async with rag_client as client: ...`
# ---------------------------------------------------------------------------
@pytest_asyncio.fixture
async def rag_client(mock_qdrant_client, mock_pg_session, mock_minio_client):
    """
    Returns an httpx.AsyncClient pointed at the RAG API ASGI app.
    All external backends (Qdrant, Postgres, MinIO, Ollama) are mocked.
    The lifespan (startup) is also patched to avoid real connection attempts.
    """
    with (
        patch("app.db.qdrant.init_qdrant", new_callable=AsyncMock),
        patch("app.db.postgres.init_postgres", new_callable=AsyncMock),
        patch("app.db.minio.init_minio", new_callable=AsyncMock),
        # Patch at the usage site — health.py and ingest.py do
        # `from app.db.xxx import yyy`, so the name is bound locally
        # in each router module. Patching the source module has no effect.
        patch("app.routers.health.get_qdrant", return_value=mock_qdrant_client),
        patch("app.routers.health.get_session", return_value=mock_pg_session),
        patch("app.routers.ingest.get_qdrant", return_value=mock_qdrant_client),
        patch("app.routers.ingest.get_session", return_value=mock_pg_session),
        patch("app.routers.ingest.get_minio", return_value=mock_minio_client),
    ):
        # Import app AFTER patches are in place
        from app.main import app

        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
        ) as client:
            yield client
