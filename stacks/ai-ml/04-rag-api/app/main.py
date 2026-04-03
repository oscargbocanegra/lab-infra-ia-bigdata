"""
Lab RAG API — Main entrypoint
FastAPI application that orchestrates:
- Document ingestion (chunk → embed → store in Qdrant + pgvector)
- RAG queries (embed → search → LLM answer)
- Collection management
"""

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager
import logging

from app.config import settings
from app.routers import ingest, query, collections, health
from app.db.qdrant import init_qdrant
from app.db.postgres import init_postgres
from app.db.minio import init_minio

logging.basicConfig(
    level=getattr(logging, settings.log_level),
    format="%(asctime)s [%(levelname)s] %(name)s — %(message)s",
)
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Initialize all connections on startup."""
    logger.info("Starting RAG API — initializing backends...")
    await init_postgres()
    await init_qdrant()
    await init_minio()
    logger.info("All backends ready. RAG API is up.")
    yield
    logger.info("Shutting down RAG API.")


app = FastAPI(
    title=settings.api_title,
    version=settings.api_version,
    description=(
        "RAG pipeline API — ingest documents, generate embeddings, "
        "store in Qdrant + pgvector, query with Ollama LLMs."
    ),
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(health.router, tags=["Health"])
app.include_router(ingest.router, prefix="/ingest", tags=["Ingestion"])
app.include_router(query.router, prefix="/query", tags=["Query"])
app.include_router(collections.router, prefix="/collections", tags=["Collections"])
