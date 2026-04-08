"""
test_health.py — RAG API health endpoint tests
================================================
Tests the GET /health endpoint behavior:
  - Happy path: all backends healthy → status "ok"
  - Degraded: Qdrant unreachable → status "degraded"
  - Degraded: Postgres unreachable → status "degraded"

No real services needed — all backends are mocked via conftest.py fixtures.
"""

from unittest.mock import AsyncMock, patch

import pytest


@pytest.mark.asyncio
async def test_health_all_backends_ok(rag_client):
    """Health endpoint returns 200 and status=ok when all backends respond."""
    response = await rag_client.get("/health")

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "ok"
    assert "backends" in body
    assert body["backends"]["qdrant"]["status"] == "ok"
    assert body["backends"]["postgres"]["status"] == "ok"


@pytest.mark.asyncio
async def test_health_degraded_when_qdrant_fails(mock_pg_session, mock_minio_client):
    """Health endpoint returns 200 but status=degraded when Qdrant is unreachable."""
    # Qdrant client raises a connection error
    broken_qdrant = AsyncMock()
    broken_qdrant.get_collections.side_effect = ConnectionError("Qdrant unavailable")

    with (
        patch("app.db.qdrant.init_qdrant", new_callable=AsyncMock),
        patch("app.db.postgres.init_postgres", new_callable=AsyncMock),
        patch("app.db.minio.init_minio", new_callable=AsyncMock),
        patch("app.routers.health.get_qdrant", return_value=broken_qdrant),
        patch("app.routers.health.get_session", return_value=mock_pg_session),
    ):
        from httpx import ASGITransport, AsyncClient

        from app.main import app

        async with AsyncClient(
            transport=ASGITransport(app=app), base_url="http://test"
        ) as client:
            response = await client.get("/health")

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "degraded"
    assert body["backends"]["qdrant"]["status"] == "error"
    assert body["backends"]["postgres"]["status"] == "ok"


@pytest.mark.asyncio
async def test_health_degraded_when_postgres_fails(
    mock_qdrant_client, mock_minio_client
):
    """Health endpoint returns 200 but status=degraded when Postgres is unreachable."""
    # Postgres session raises on execute
    broken_session = AsyncMock()
    broken_session.execute.side_effect = Exception("Postgres connection refused")
    broken_session_cm = AsyncMock()
    broken_session_cm.__aenter__.return_value = broken_session
    broken_session_cm.__aexit__.return_value = None

    with (
        patch("app.db.qdrant.init_qdrant", new_callable=AsyncMock),
        patch("app.db.postgres.init_postgres", new_callable=AsyncMock),
        patch("app.db.minio.init_minio", new_callable=AsyncMock),
        patch("app.routers.health.get_qdrant", return_value=mock_qdrant_client),
        patch("app.routers.health.get_session", return_value=broken_session_cm),
    ):
        from httpx import ASGITransport, AsyncClient

        from app.main import app

        async with AsyncClient(
            transport=ASGITransport(app=app), base_url="http://test"
        ) as client:
            response = await client.get("/health")

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "degraded"
    assert body["backends"]["postgres"]["status"] == "error"
    assert body["backends"]["qdrant"]["status"] == "ok"


@pytest.mark.asyncio
async def test_health_response_schema(rag_client):
    """Health response always includes 'status' and 'backends' keys."""
    response = await rag_client.get("/health")
    body = response.json()

    assert "status" in body
    assert "backends" in body
    assert isinstance(body["backends"], dict)
