"""
conftest.py — Agent test fixtures
===================================
Patches all external dependencies so tests run without a real cluster:
  - Ollama HTTP calls  → httpx mocked responses
  - Qdrant client      → AsyncMock
  - Postgres           → AsyncMock
  - OpenSearch (traces)→ MagicMock
  - LangGraph graph    → patched at compile time

The app is tested via ASGI transport (no real server needed).
"""

import os
import sys
from unittest.mock import AsyncMock, MagicMock, patch

from httpx import ASGITransport, AsyncClient
import pytest
import pytest_asyncio

# ---------------------------------------------------------------------------
# Ensure the agent app is importable from tests/
# The app lives at: stacks/ai-ml/06-agent/
# ---------------------------------------------------------------------------
AGENT_PATH = os.path.join(
    os.path.dirname(__file__),
    "..",
    "..",
    "stacks",
    "ai-ml",
    "06-agent",
)
sys.path.insert(0, os.path.abspath(AGENT_PATH))


# ---------------------------------------------------------------------------
# Qdrant mock — async client
# ---------------------------------------------------------------------------
@pytest.fixture
def mock_qdrant():
    client = AsyncMock()
    # search returns empty list by default
    client.search.return_value = []
    return client


# ---------------------------------------------------------------------------
# Postgres async engine mock
# ---------------------------------------------------------------------------
@pytest.fixture
def mock_pg():
    session = AsyncMock()
    session.execute.return_value = AsyncMock(
        fetchall=MagicMock(return_value=[]),
        keys=MagicMock(return_value=[]),
    )
    return session


# ---------------------------------------------------------------------------
# OpenSearch mock — write_trace should not fail tests
# ---------------------------------------------------------------------------
@pytest.fixture
def mock_opensearch():
    client = MagicMock()
    client.index.return_value = {"result": "created"}
    return client


# ---------------------------------------------------------------------------
# Full agent ASGI client — patches Ollama + Qdrant + Postgres + OpenSearch
# ---------------------------------------------------------------------------
@pytest_asyncio.fixture
async def agent_client(mock_qdrant, mock_pg, mock_opensearch):
    """
    Returns an httpx.AsyncClient pointed at the Agent ASGI app.
    - LangGraph graph is compiled but all node Ollama calls are mocked.
    - Qdrant search returns empty (no documents in test corpus).
    - Postgres queries return empty results.
    - OpenSearch trace writes are no-ops.
    """
    # Mock Ollama responses for router + synthesizer + embeddings
    # The router will return "rag" by default (mocked response)
    mock_ollama_response = MagicMock()
    mock_ollama_response.status_code = 200
    mock_ollama_response.json.return_value = {
        "response": "rag",
        "done": True,
    }
    mock_ollama_response.raise_for_status = MagicMock()

    mock_embed_response = MagicMock()
    mock_embed_response.status_code = 200
    mock_embed_response.json.return_value = {"embeddings": [[0.1] * 768]}
    mock_embed_response.raise_for_status = MagicMock()

    async def mock_post(url, **kwargs):
        if "/api/embed" in url:
            return mock_embed_response
        # Default: return "rag" route or simple answer
        resp = MagicMock()
        resp.status_code = 200
        resp.raise_for_status = MagicMock()
        if "/api/generate" in url:
            prompt = kwargs.get("json", {}).get("prompt", "")
            # Router prompt → return route
            if "routing assistant" in prompt.lower() or "category:" in prompt.lower():
                resp.json.return_value = {"response": "rag", "done": True}
            else:
                resp.json.return_value = {
                    "response": "Based on the available context, I can answer your question.",
                    "done": True,
                }
        return resp

    with (
        patch("app.nodes.router.httpx.AsyncClient") as mock_router_client,
        patch("app.nodes.rag.httpx.AsyncClient") as mock_rag_client,
        patch("app.nodes.synthesizer.httpx.AsyncClient") as mock_synth_client,
        patch("app.nodes.rag.get_qdrant", return_value=mock_qdrant),
        patch("app.nodes.data.asyncpg")
        if False
        else patch("app.nodes.data.asyncpg", MagicMock()),
        patch("app.tracing.OpenSearch", return_value=mock_opensearch),
    ):
        # Configure all httpx.AsyncClient mocks to use our mock_post
        for mock_client in [mock_router_client, mock_rag_client, mock_synth_client]:
            instance = AsyncMock()
            instance.__aenter__.return_value = instance
            instance.__aexit__.return_value = None
            instance.post = AsyncMock(side_effect=mock_post)
            mock_client.return_value = instance

        from app.main import app

        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
        ) as client:
            yield client
