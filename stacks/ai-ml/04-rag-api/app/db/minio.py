"""MinIO client initialization — document raw storage."""

import logging

from minio import Minio

from app.config import settings

logger = logging.getLogger(__name__)

_client: Minio | None = None


def get_minio() -> Minio:
    if _client is None:
        raise RuntimeError("MinIO client not initialized")
    return _client


async def init_minio() -> None:
    global _client

    _client = Minio(
        endpoint=settings.minio_endpoint,
        access_key=settings.minio_access_key,
        secret_key=settings.minio_secret_key,
        secure=settings.minio_secure,
    )

    # Ensure RAG bucket exists
    if not _client.bucket_exists(settings.minio_bucket):
        _client.make_bucket(settings.minio_bucket)
        logger.info("Created MinIO bucket: %s", settings.minio_bucket)
    else:
        logger.info("MinIO bucket exists: %s", settings.minio_bucket)

    logger.info("MinIO initialized — endpoint: %s", settings.minio_endpoint)
