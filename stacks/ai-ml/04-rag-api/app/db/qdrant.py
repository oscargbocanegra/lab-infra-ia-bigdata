"""Qdrant client initialization and helpers."""

import logging
from qdrant_client import AsyncQdrantClient
from qdrant_client.models import Distance, VectorParams, HnswConfigDiff
from app.config import settings

logger = logging.getLogger(__name__)

_client: AsyncQdrantClient | None = None


def get_qdrant() -> AsyncQdrantClient:
    if _client is None:
        raise RuntimeError("Qdrant client not initialized")
    return _client


async def init_qdrant() -> None:
    global _client
    _client = AsyncQdrantClient(
        url=settings.qdrant_url,
        api_key=settings.qdrant_api_key or None,
    )

    # Ensure default collections exist
    collections_to_create = [
        (
            f"{settings.qdrant_collection_prefix}documents_nomic",
            768,  # nomic-embed-text dims
        ),
        (
            f"{settings.qdrant_collection_prefix}documents_bge",
            1024,  # bge-m3 dims
        ),
    ]

    existing = {c.name for c in (await _client.get_collections()).collections}

    for name, dims in collections_to_create:
        if name not in existing:
            await _client.create_collection(
                collection_name=name,
                vectors_config=VectorParams(
                    size=dims,
                    distance=Distance.COSINE,
                ),
                hnsw_config=HnswConfigDiff(
                    m=16,
                    ef_construct=100,
                    full_scan_threshold=10_000,
                ),
            )
            logger.info("Created Qdrant collection: %s (%d dims)", name, dims)
        else:
            logger.info("Qdrant collection already exists: %s", name)

    logger.info("Qdrant initialized — %d collections ready", len(collections_to_create))
