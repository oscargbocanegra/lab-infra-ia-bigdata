"""
RAG Node — semantic search via Qdrant.

Flow:
  1. Embed question via Ollama (nomic-embed-text)
  2. Search Qdrant collection for top-K similar chunks
  3. Format retrieved chunks into a context string
"""

import logging

import httpx
from qdrant_client import AsyncQdrantClient

from app.config import settings
from app.state import AgentState

logger = logging.getLogger(__name__)

_qdrant_client: AsyncQdrantClient | None = None


def get_qdrant() -> AsyncQdrantClient:
    global _qdrant_client
    if _qdrant_client is None:
        _qdrant_client = AsyncQdrantClient(
            url=settings.qdrant_url,
            api_key=settings.qdrant_api_key or None,
        )
    return _qdrant_client


async def rag_node(state: AgentState) -> dict:
    """
    Perform semantic search in Qdrant and return context chunks.
    """
    question = state["question"]
    logger.info("[RAG] Embedding question for semantic search")

    # 1. Embed question
    async with httpx.AsyncClient(timeout=60.0) as client:
        resp = await client.post(
            f"{settings.ollama_base_url}/api/embed",
            json={"model": settings.embed_model, "input": [question]},
        )
        resp.raise_for_status()
        question_vector = resp.json()["embeddings"][0]

    # 2. Search Qdrant
    qdrant = get_qdrant()
    results = await qdrant.search(
        collection_name=settings.qdrant_collection,
        query_vector=question_vector,
        limit=settings.top_k,
        with_payload=True,
    )

    logger.info("[RAG] Retrieved %d chunks from Qdrant", len(results))

    # 3. Build chunks list and context string
    chunks = [
        {
            "filename": r.payload.get("filename", "unknown"),
            "chunk_index": r.payload.get("chunk_index", 0),
            "chunk_text": r.payload.get("chunk_text", ""),
            "score": round(r.score, 4),
        }
        for r in results
    ]

    context = (
        "\n\n---\n\n".join(
            f"[Source: {c['filename']}, chunk {c['chunk_index']} | score: {c['score']}]\n{c['chunk_text']}"
            for c in chunks
        )
        if chunks
        else "No relevant documents found."
    )

    return {
        "rag_chunks": chunks,
        "rag_context": context,
        "chunks_retrieved": len(chunks),
    }
