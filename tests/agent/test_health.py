"""
test_health.py — Agent API health endpoint tests
=================================================
Tests the GET /health endpoint:
  - Returns 200 with status=ok
  - Response includes version field
"""

import pytest


@pytest.mark.asyncio
async def test_health_returns_ok(agent_client):
    """GET /health returns 200 and status=ok."""
    response = await agent_client.get("/health")

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "ok"


@pytest.mark.asyncio
async def test_health_includes_version(agent_client):
    """GET /health response includes the API version."""
    response = await agent_client.get("/health")

    assert response.status_code == 200
    body = response.json()
    assert "version" in body
    assert body["version"]  # non-empty


@pytest.mark.asyncio
async def test_health_does_not_require_auth(agent_client):
    """Health endpoint is unauthenticated — always accessible."""
    response = await agent_client.get("/health")
    assert response.status_code != 401
    assert response.status_code != 403
