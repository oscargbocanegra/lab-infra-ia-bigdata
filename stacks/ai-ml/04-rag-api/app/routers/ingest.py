"""
Ingestion router — upload documents, chunk, embed, store in Qdrant + pgvector + MinIO.

Flow:
  1. Receive file (PDF, TXT, DOCX, MD)
  2. Upload raw file to MinIO (rag-documents bucket)
  3. Extract text and split into chunks (LangChain splitter)
  4. Embed each chunk via Ollama (nomic-embed-text)
  5. Upsert vectors into Qdrant collection
  6. Store metadata + chunk text in Postgres (documents table)
"""

import io
import uuid
import logging
from fastapi import APIRouter, UploadFile, File, Form, HTTPException
from pydantic import BaseModel
import httpx

from app.config import settings
from app.db.qdrant import get_qdrant
from app.db.postgres import get_session
from app.db.minio import get_minio
from langchain_text_splitters import RecursiveCharacterTextSplitter
from qdrant_client.models import PointStruct
from sqlalchemy import text

logger = logging.getLogger(__name__)
router = APIRouter()


class IngestResponse(BaseModel):
    document_id: str
    collection: str
    filename: str
    chunks_indexed: int
    minio_path: str


def _extract_text(content: bytes, filename: str) -> str:
    """Extract plain text from PDF, DOCX, or text file."""
    if filename.endswith(".pdf"):
        from pypdf import PdfReader

        reader = PdfReader(io.BytesIO(content))
        return "\n".join(p.extract_text() or "" for p in reader.pages)
    elif filename.endswith(".docx"):
        from docx import Document

        doc = Document(io.BytesIO(content))
        return "\n".join(p.text for p in doc.paragraphs)
    else:
        # Plain text / markdown
        return content.decode("utf-8", errors="replace")


async def _embed(texts: list[str]) -> list[list[float]]:
    """Generate embeddings via Ollama embed endpoint."""
    async with httpx.AsyncClient(timeout=120.0) as client:
        resp = await client.post(
            f"{settings.ollama_base_url}/api/embed",
            json={"model": settings.embed_model, "input": texts},
        )
        resp.raise_for_status()
        data = resp.json()
        return data["embeddings"]


@router.post("/", response_model=IngestResponse)
async def ingest_document(
    file: UploadFile = File(...),
    collection: str = Form(default="default"),
):
    """
    Ingest a document: chunk → embed → store in Qdrant + pgvector + MinIO.

    - **file**: PDF, TXT, DOCX, or MD file
    - **collection**: logical collection name (default: 'default')
    """
    content = await file.read()
    filename = file.filename or "unknown"
    doc_id = str(uuid.uuid4())
    qdrant_collection = f"{settings.qdrant_collection_prefix}documents_nomic"

    # 1. Upload raw file to MinIO
    minio_path = f"{collection}/{doc_id}/{filename}"
    minio = get_minio()
    minio.put_object(
        settings.minio_bucket,
        minio_path,
        io.BytesIO(content),
        length=len(content),
        content_type=file.content_type or "application/octet-stream",
    )
    logger.info("Uploaded to MinIO: %s", minio_path)

    # 2. Extract text
    raw_text = _extract_text(content, filename)
    if not raw_text.strip():
        raise HTTPException(
            status_code=422, detail="Could not extract text from document"
        )

    # 3. Chunk
    splitter = RecursiveCharacterTextSplitter(
        chunk_size=settings.chunk_size,
        chunk_overlap=settings.chunk_overlap,
        separators=["\n\n", "\n", " ", ""],
    )
    chunks = splitter.split_text(raw_text)
    logger.info("Document '%s' split into %d chunks", filename, len(chunks))

    # 4. Embed (batch all chunks)
    embeddings = await _embed(chunks)

    # 5. Upsert into Qdrant
    qdrant = get_qdrant()
    points = [
        PointStruct(
            id=str(uuid.uuid4()),
            vector=embedding,
            payload={
                "doc_id": doc_id,
                "collection": collection,
                "filename": filename,
                "chunk_index": i,
                "chunk_text": chunk,
                "minio_path": minio_path,
            },
        )
        for i, (chunk, embedding) in enumerate(zip(chunks, embeddings))
    ]
    await qdrant.upsert(collection_name=qdrant_collection, points=points)
    logger.info(
        "Upserted %d vectors into Qdrant collection '%s'",
        len(points),
        qdrant_collection,
    )

    # 6. Store metadata + chunks in Postgres
    async with get_session() as session:
        for i, (chunk, embedding) in enumerate(zip(chunks, embeddings)):
            result = await session.execute(
                text("""
                    INSERT INTO documents
                        (collection, filename, source_url, chunk_index, chunk_text,
                         token_count, model, metadata)
                    VALUES
                        (:collection, :filename, :source_url, :chunk_index, :chunk_text,
                         :token_count, :model, :metadata)
                    RETURNING id
                """),
                {
                    "collection": collection,
                    "filename": filename,
                    "source_url": minio_path,
                    "chunk_index": i,
                    "chunk_text": chunk,
                    "token_count": len(chunk.split()),
                    "model": settings.embed_model,
                    "metadata": "{}",
                },
            )
            pg_doc_id = result.scalar_one()

            # Store embedding in pgvector
            await session.execute(
                text("""
                    INSERT INTO embeddings (document_id, embedding)
                    VALUES (:doc_id, :embedding)
                """),
                {"doc_id": pg_doc_id, "embedding": str(embedding)},
            )
        await session.commit()

    logger.info("Document '%s' fully indexed — %d chunks", filename, len(chunks))

    return IngestResponse(
        document_id=doc_id,
        collection=collection,
        filename=filename,
        chunks_indexed=len(chunks),
        minio_path=minio_path,
    )
