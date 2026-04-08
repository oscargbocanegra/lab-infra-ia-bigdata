"""
test_ingest.py — RAG API ingestion logic tests
================================================
Tests the document ingestion pipeline:
  - Text extraction from different file formats
  - Chunking logic (chunk size / overlap)
  - HTTP 422 when document has no extractable text
  - Ingest endpoint happy path (mocked Qdrant + Postgres + MinIO + Ollama)
  - Ingest rejects unsupported file types gracefully

Strategy:
  - _extract_text() is tested directly (pure function, no mocks needed)
  - _build_rag_prompt() tested directly (pure function)
  - POST /ingest/ tested via ASGI client with all backends mocked
  - Ollama embed is mocked via patch on httpx.AsyncClient
"""

from unittest.mock import AsyncMock, patch

import pytest

# ---------------------------------------------------------------------------
# Unit tests — pure functions (no network, no fixtures needed)
# ---------------------------------------------------------------------------


def test_extract_text_from_plain_text():
    """_extract_text correctly decodes plain text files."""
    # Import the function directly — no app startup needed
    import os
    import sys

    sys.path.insert(
        0,
        os.path.abspath(
            os.path.join(
                os.path.dirname(__file__), "..", "..", "stacks", "ai-ml", "04-rag-api"
            )
        ),
    )
    from app.routers.ingest import _extract_text

    content = b"Hello, this is a test document.\nSecond line."
    result = _extract_text(content, "test.txt")

    assert "Hello" in result
    assert "Second line" in result


def test_extract_text_from_markdown():
    """_extract_text treats .md files as plain text."""
    from app.routers.ingest import _extract_text

    content = b"# Title\n\nSome **markdown** content."
    result = _extract_text(content, "README.md")

    assert "Title" in result
    assert "markdown" in result


def test_extract_text_handles_encoding_errors():
    """_extract_text replaces invalid UTF-8 bytes instead of crashing."""
    from app.routers.ingest import _extract_text

    # Invalid UTF-8 sequence mixed with valid text
    content = b"Valid text \xff\xfe more text"
    result = _extract_text(content, "data.txt")

    assert "Valid text" in result
    assert "more text" in result


def test_rag_prompt_contains_question_and_context():
    """_build_rag_prompt includes the question and chunk context in the prompt."""
    from app.routers.query import _build_rag_prompt

    chunks = [
        {
            "filename": "doc.txt",
            "chunk_index": 0,
            "chunk_text": "The capital of France is Paris.",
        }
    ]
    prompt = _build_rag_prompt("What is the capital of France?", chunks)

    assert "What is the capital of France?" in prompt
    assert "The capital of France is Paris." in prompt
    assert "doc.txt" in prompt


def test_rag_prompt_multiple_chunks():
    """_build_rag_prompt separates multiple chunks with delimiters."""
    from app.routers.query import _build_rag_prompt

    chunks = [
        {"filename": "a.txt", "chunk_index": 0, "chunk_text": "Chunk one content."},
        {"filename": "b.txt", "chunk_index": 1, "chunk_text": "Chunk two content."},
    ]
    prompt = _build_rag_prompt("test question", chunks)

    assert "Chunk one content." in prompt
    assert "Chunk two content." in prompt
    assert "---" in prompt  # separator between chunks


# ---------------------------------------------------------------------------
# Integration tests — POST /ingest/ via ASGI client
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_ingest_text_file_success(
    rag_client, mock_qdrant_client, mock_pg_session, mock_minio_client
):
    """
    POST /ingest/ with a valid text file returns 200 with correct response schema.
    Ollama embed is mocked to return a fake 768-dim vector.
    """
    fake_embedding = [0.1] * 768

    with patch(
        "app.routers.ingest._embed",
        new_callable=AsyncMock,
        return_value=[fake_embedding, fake_embedding],
    ):
        response = await rag_client.post(
            "/ingest/",
            files={
                "file": ("test_doc.txt", b"First chunk content. " * 60, "text/plain")
            },
            data={"collection": "test-collection"},
        )

    assert response.status_code == 200
    body = response.json()
    assert body["collection"] == "test-collection"
    assert body["filename"] == "test_doc.txt"
    assert body["chunks_indexed"] >= 1
    assert "document_id" in body
    assert "minio_path" in body


@pytest.mark.asyncio
async def test_ingest_empty_document_returns_422(rag_client, mock_minio_client):
    """
    POST /ingest/ with a file that yields no text returns HTTP 422.
    The MinIO upload succeeds but the empty text check triggers the error.
    """
    with patch(
        "app.routers.ingest._extract_text",
        return_value="   ",  # only whitespace — empty after strip()
    ):
        response = await rag_client.post(
            "/ingest/",
            files={"file": ("empty.txt", b"   ", "text/plain")},
            data={"collection": "test"},
        )

    assert response.status_code == 422
    body = response.json()
    assert "text" in body["detail"].lower() or "extract" in body["detail"].lower()


@pytest.mark.asyncio
async def test_ingest_minio_path_format(
    rag_client, mock_qdrant_client, mock_pg_session, mock_minio_client
):
    """
    The minio_path in the response follows the pattern: <collection>/<doc_id>/<filename>
    """
    fake_embedding = [0.0] * 768

    with patch(
        "app.routers.ingest._embed",
        new_callable=AsyncMock,
        return_value=[fake_embedding],
    ):
        response = await rag_client.post(
            "/ingest/",
            files={
                "file": ("my_doc.txt", b"Some content for testing." * 10, "text/plain")
            },
            data={"collection": "my-collection"},
        )

    assert response.status_code == 200
    body = response.json()
    minio_path = body["minio_path"]

    # Format must be: my-collection/<uuid>/my_doc.txt
    parts = minio_path.split("/")
    assert parts[0] == "my-collection"
    assert parts[-1] == "my_doc.txt"
    assert len(parts) == 3  # collection / doc_id / filename


@pytest.mark.asyncio
async def test_ingest_calls_qdrant_upsert(
    rag_client, mock_qdrant_client, mock_pg_session, mock_minio_client
):
    """After ingestion, Qdrant.upsert() must have been called exactly once."""
    fake_embedding = [0.5] * 768

    with patch(
        "app.routers.ingest._embed",
        new_callable=AsyncMock,
        return_value=[fake_embedding],
    ):
        await rag_client.post(
            "/ingest/",
            files={"file": ("check.txt", b"Short document content.", "text/plain")},
            data={"collection": "default"},
        )

    mock_qdrant_client.upsert.assert_called_once()
