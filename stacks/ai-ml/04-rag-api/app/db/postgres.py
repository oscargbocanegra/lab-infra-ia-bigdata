"""PostgreSQL + pgvector client initialization."""

import logging

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.config import settings

logger = logging.getLogger(__name__)

_engine = None
_session_factory: async_sessionmaker | None = None


def get_session() -> AsyncSession:
    if _session_factory is None:
        raise RuntimeError("Postgres not initialized")
    return _session_factory()


async def init_postgres() -> None:
    global _engine, _session_factory

    # Use asyncpg driver for async SQLAlchemy
    dsn = settings.pg_dsn.replace("postgresql+psycopg2://", "postgresql+asyncpg://")

    _engine = create_async_engine(dsn, pool_size=5, max_overflow=10, echo=False)
    _session_factory = async_sessionmaker(_engine, expire_on_commit=False)

    # Verify connection and pgvector extension
    async with _engine.connect() as conn:
        result = await conn.execute(
            text("SELECT extname FROM pg_extension WHERE extname = 'vector'")
        )
        row = result.fetchone()
        if row:
            logger.info("Postgres connected — pgvector extension active")
        else:
            logger.warning(
                "Postgres connected but pgvector extension NOT found in DB 'rag'"
            )
