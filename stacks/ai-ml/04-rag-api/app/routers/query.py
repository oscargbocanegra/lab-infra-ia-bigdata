"""
Query router — RAG query pipeline.

Flow:
  1. Embed the user question via Ollama
  2. Search Qdrant for top-K similar chunks
  3. Build context from retrieved chunks
  4. Generate answer via Ollama LLM (streaming supported)
"""

import logging
from fastapi import APIRouter, HTTPException
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
import httpx
import json

from app.config import settings
from app.db.qdrant import get_qdrant

logger = logging.getLogger(__name__)
router = APIRouter()


class QueryRequest(BaseModel):
    question: str
    collection: str = "default"
    top_k: int | None = None
    model: str | None = None
    stream: bool = False


class SourceChunk(BaseModel):
    filename: str
    chunk_index: int
    chunk_text: str
    score: float


class QueryResponse(BaseModel):
    question: str
    answer: str
    sources: list[SourceChunk]
    model: str
    collection: str


async def _embed_single(text: str) -> list[float]:
    async with httpx.AsyncClient(timeout=60.0) as client:
        resp = await client.post(
            f"{settings.ollama_base_url}/api/embed",
            json={"model": settings.embed_model, "input": [text]},
        )
        resp.raise_for_status()
        return resp.json()["embeddings"][0]


async def _generate(prompt: str, model: str, stream: bool = False):
    """Call Ollama generate endpoint."""
    payload = {
        "model": model,
        "prompt": prompt,
        "stream": stream,
        "options": {
            "temperature": 0.2,
            "num_predict": 1024,
        },
    }
    async with httpx.AsyncClient(timeout=300.0) as client:
        if stream:
            async with client.stream(
                "POST",
                f"{settings.ollama_base_url}/api/generate",
                json=payload,
            ) as resp:
                resp.raise_for_status()
                async for line in resp.aiter_lines():
                    if line:
                        yield line
        else:
            resp = await client.post(
                f"{settings.ollama_base_url}/api/generate",
                json=payload,
            )
            resp.raise_for_status()
            yield resp.json()["response"]


def _build_rag_prompt(question: str, chunks: list[dict]) -> str:
    context = "\n\n---\n\n".join(
        f"[Source: {c['filename']}, chunk {c['chunk_index']}]\n{c['chunk_text']}"
        for c in chunks
    )
    return f"""You are a helpful assistant. Answer the question based ONLY on the provided context.
If the answer is not in the context, say "I don't have enough information to answer that."

CONTEXT:
{context}

QUESTION: {question}

ANSWER:"""


@router.post("/", response_model=QueryResponse)
async def rag_query(req: QueryRequest):
    """
    RAG query: embed question → Qdrant search → LLM answer.

    - **question**: the user's question
    - **collection**: which document collection to search
    - **top_k**: number of chunks to retrieve (default from config)
    - **model**: LLM model to use (default: qwen2.5:7b)
    - **stream**: whether to stream the response (use /query/stream endpoint for SSE)
    """
    top_k = req.top_k or settings.top_k
    model = req.model or settings.llm_model
    qdrant_collection = f"{settings.qdrant_collection_prefix}documents_nomic"

    # 1. Embed the question
    question_vector = await _embed_single(req.question)

    # 2. Search Qdrant
    qdrant = get_qdrant()
    results = await qdrant.search(
        collection_name=qdrant_collection,
        query_vector=question_vector,
        limit=top_k,
        query_filter=None
        if req.collection == "default"
        else {"must": [{"key": "collection", "match": {"value": req.collection}}]},
        with_payload=True,
    )

    if not results:
        raise HTTPException(
            status_code=404,
            detail=f"No relevant chunks found in collection '{req.collection}'",
        )

    # 3. Build context
    chunks = [
        {
            "filename": r.payload.get("filename", "unknown"),
            "chunk_index": r.payload.get("chunk_index", 0),
            "chunk_text": r.payload.get("chunk_text", ""),
            "score": r.score,
        }
        for r in results
    ]

    prompt = _build_rag_prompt(req.question, chunks)

    # 4. Generate answer
    answer_parts = []
    async for part in _generate(prompt, model, stream=False):
        answer_parts.append(part)
    answer = "".join(answer_parts)

    return QueryResponse(
        question=req.question,
        answer=answer,
        sources=[
            SourceChunk(
                filename=c["filename"],
                chunk_index=c["chunk_index"],
                chunk_text=c["chunk_text"][:300] + "..."
                if len(c["chunk_text"]) > 300
                else c["chunk_text"],
                score=c["score"],
            )
            for c in chunks
        ],
        model=model,
        collection=req.collection,
    )


@router.post("/stream")
async def rag_query_stream(req: QueryRequest):
    """RAG query with SSE streaming — returns Server-Sent Events."""
    top_k = req.top_k or settings.top_k
    model = req.model or settings.llm_model
    qdrant_collection = f"{settings.qdrant_collection_prefix}documents_nomic"

    question_vector = await _embed_single(req.question)

    qdrant = get_qdrant()
    results = await qdrant.search(
        collection_name=qdrant_collection,
        query_vector=question_vector,
        limit=top_k,
        with_payload=True,
    )

    chunks = [
        {
            "filename": r.payload.get("filename", "unknown"),
            "chunk_index": r.payload.get("chunk_index", 0),
            "chunk_text": r.payload.get("chunk_text", ""),
        }
        for r in results
    ]

    prompt = _build_rag_prompt(req.question, chunks)

    async def event_generator():
        # First emit the sources
        sources_data = json.dumps({"type": "sources", "data": chunks})
        yield f"data: {sources_data}\n\n"

        # Then stream the LLM response
        async for line in _generate(prompt, model, stream=True):
            try:
                token_data = json.loads(line)
                if token := token_data.get("response"):
                    yield f"data: {json.dumps({'type': 'token', 'data': token})}\n\n"
                if token_data.get("done"):
                    yield f"data: {json.dumps({'type': 'done'})}\n\n"
            except json.JSONDecodeError:
                pass

    return StreamingResponse(event_generator(), media_type="text/event-stream")
