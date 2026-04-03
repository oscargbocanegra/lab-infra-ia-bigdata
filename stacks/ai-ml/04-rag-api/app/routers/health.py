"""Health check router."""

from fastapi import APIRouter
from app.db.qdrant import get_qdrant
from app.db.postgres import get_session
from sqlalchemy import text

router = APIRouter()


@router.get("/health")
async def health():
    """Liveness probe — check all backends are reachable."""
    status = {"status": "ok", "backends": {}}

    # Qdrant
    try:
        client = get_qdrant()
        cols = await client.get_collections()
        status["backends"]["qdrant"] = {
            "status": "ok",
            "collections": len(cols.collections),
        }
    except Exception as e:
        status["backends"]["qdrant"] = {"status": "error", "detail": str(e)}
        status["status"] = "degraded"

    # Postgres
    try:
        async with get_session() as session:
            await session.execute(text("SELECT 1"))
        status["backends"]["postgres"] = {"status": "ok"}
    except Exception as e:
        status["backends"]["postgres"] = {"status": "error", "detail": str(e)}
        status["status"] = "degraded"

    return status
