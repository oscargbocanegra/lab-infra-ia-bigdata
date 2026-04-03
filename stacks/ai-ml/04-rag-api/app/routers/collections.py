"""Collections management router — list, inspect and delete Qdrant collections."""

import logging
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from app.db.qdrant import get_qdrant
from app.config import settings

logger = logging.getLogger(__name__)
router = APIRouter()


class CollectionInfo(BaseModel):
    name: str
    vectors_count: int | None = None
    status: str | None = None


@router.get("/", response_model=list[CollectionInfo])
async def list_collections():
    """List all Qdrant collections with basic stats."""
    qdrant = get_qdrant()
    cols = await qdrant.get_collections()
    result = []
    for c in cols.collections:
        try:
            info = await qdrant.get_collection(c.name)
            result.append(
                CollectionInfo(
                    name=c.name,
                    vectors_count=info.vectors_count,
                    status=str(info.status),
                )
            )
        except Exception:
            result.append(CollectionInfo(name=c.name))
    return result


@router.get("/{name}", response_model=CollectionInfo)
async def get_collection(name: str):
    """Get details for a specific collection."""
    qdrant = get_qdrant()
    try:
        info = await qdrant.get_collection(name)
        return CollectionInfo(
            name=name,
            vectors_count=info.vectors_count,
            status=str(info.status),
        )
    except Exception as e:
        raise HTTPException(
            status_code=404, detail=f"Collection '{name}' not found: {e}"
        )


@router.delete("/{name}")
async def delete_collection(name: str):
    """Delete a Qdrant collection. WARNING: irreversible."""
    qdrant = get_qdrant()
    # Protect default collections
    protected = [
        f"{settings.qdrant_collection_prefix}documents_nomic",
        f"{settings.qdrant_collection_prefix}documents_bge",
    ]
    if name in protected:
        raise HTTPException(
            status_code=403,
            detail=f"Cannot delete protected collection '{name}'",
        )
    try:
        await qdrant.delete_collection(name)
        logger.info("Deleted Qdrant collection: %s", name)
        return {"deleted": name}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
