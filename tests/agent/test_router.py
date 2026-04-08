"""
test_router.py — Router node logic tests
=========================================
Tests the route_condition function and router_node Ollama response parsing.

The router_node makes HTTP calls to Ollama. We test:
  1. route_condition() — pure function, no mocks needed
  2. router_node() — mocked httpx, testing sanitization logic
     - "rag" response → route = "rag"
     - "data" response → route = "data"
     - "both" response → route = "both"
     - ambiguous/garbage response → fallback to "rag"

No LangGraph graph compilation needed — we test nodes in isolation.
"""

import os
import sys
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

# Ensure agent app is importable
AGENT_PATH = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..", "..", "stacks", "ai-ml", "06-agent")
)
if AGENT_PATH not in sys.path:
    sys.path.insert(0, AGENT_PATH)


# ---------------------------------------------------------------------------
# Unit tests — route_condition() pure function
# ---------------------------------------------------------------------------


def test_route_condition_returns_rag():
    """route_condition maps route='rag' to the 'rag' edge."""
    from app.nodes.router import route_condition

    state = {"route": "rag", "question": "test"}
    assert route_condition(state) == "rag"


def test_route_condition_returns_data():
    """route_condition maps route='data' to the 'data' edge."""
    from app.nodes.router import route_condition

    state = {"route": "data", "question": "test"}
    assert route_condition(state) == "data"


def test_route_condition_returns_both():
    """route_condition maps route='both' to the 'both' edge."""
    from app.nodes.router import route_condition

    state = {"route": "both", "question": "test"}
    assert route_condition(state) == "both"


def test_route_condition_defaults_to_rag_when_missing():
    """route_condition defaults to 'rag' when route key is missing from state."""
    from app.nodes.router import route_condition

    state = {"question": "test"}  # no 'route' key
    assert route_condition(state) == "rag"


def test_route_condition_defaults_to_rag_on_unknown():
    """route_condition falls back to 'rag' for unrecognized route values."""
    from app.nodes.router import route_condition

    state = {"route": "unknown_value", "question": "test"}
    assert route_condition(state) == "rag"


# ---------------------------------------------------------------------------
# Unit tests — router_node() Ollama response sanitization
# ---------------------------------------------------------------------------


def _make_ollama_mock(response_text: str) -> MagicMock:
    """Helper: creates a mock httpx response with a given Ollama text."""
    resp = MagicMock()
    resp.raise_for_status = MagicMock()
    resp.json.return_value = {"response": response_text, "done": True}
    return resp


@pytest.mark.asyncio
async def test_router_node_classifies_rag():
    """router_node sets route='rag' when Ollama returns 'rag'."""
    from app.nodes.router import router_node

    mock_client = AsyncMock()
    mock_client.__aenter__.return_value = mock_client
    mock_client.__aexit__.return_value = None
    mock_client.post = AsyncMock(return_value=_make_ollama_mock("rag"))

    with patch("app.nodes.router.httpx.AsyncClient", return_value=mock_client):
        state = {
            "question": "What does the architecture document say about networking?"
        }
        result = await router_node(state)

    assert result["route"] == "rag"


@pytest.mark.asyncio
async def test_router_node_classifies_data():
    """router_node sets route='data' when Ollama returns 'data'."""
    from app.nodes.router import router_node

    mock_client = AsyncMock()
    mock_client.__aenter__.return_value = mock_client
    mock_client.__aexit__.return_value = None
    mock_client.post = AsyncMock(return_value=_make_ollama_mock("data"))

    with patch("app.nodes.router.httpx.AsyncClient", return_value=mock_client):
        state = {"question": "How many sales records are in the database?"}
        result = await router_node(state)

    assert result["route"] == "data"


@pytest.mark.asyncio
async def test_router_node_classifies_both():
    """router_node sets route='both' when Ollama returns 'both'."""
    from app.nodes.router import router_node

    mock_client = AsyncMock()
    mock_client.__aenter__.return_value = mock_client
    mock_client.__aexit__.return_value = None
    mock_client.post = AsyncMock(return_value=_make_ollama_mock("both"))

    with patch("app.nodes.router.httpx.AsyncClient", return_value=mock_client):
        state = {"question": "Show me the policy AND the count of violations"}
        result = await router_node(state)

    assert result["route"] == "both"


@pytest.mark.asyncio
async def test_router_node_defaults_to_rag_on_garbage_response():
    """
    router_node defaults to 'rag' when Ollama returns garbage/ambiguous text.
    This tests the sanitization logic — real LLMs can hallucinate.
    """
    from app.nodes.router import router_node

    mock_client = AsyncMock()
    mock_client.__aenter__.return_value = mock_client
    mock_client.__aexit__.return_value = None
    # Garbage response — not rag/data/both
    mock_client.post = AsyncMock(
        return_value=_make_ollama_mock("I think this is a complex question...")
    )

    with patch("app.nodes.router.httpx.AsyncClient", return_value=mock_client):
        state = {"question": "Something ambiguous"}
        result = await router_node(state)

    # Must default to rag — never crash, never return unknown route
    assert result["route"] == "rag"


@pytest.mark.asyncio
async def test_router_node_handles_mixed_case_response():
    """router_node correctly sanitizes uppercase/mixed case Ollama responses."""
    from app.nodes.router import router_node

    mock_client = AsyncMock()
    mock_client.__aenter__.return_value = mock_client
    mock_client.__aexit__.return_value = None
    mock_client.post = AsyncMock(return_value=_make_ollama_mock("  DATA  "))

    with patch("app.nodes.router.httpx.AsyncClient", return_value=mock_client):
        state = {"question": "Count the users"}
        result = await router_node(state)

    assert result["route"] == "data"
