"""
Trace writer — persists agent invocation telemetry to OpenSearch.

Index pattern: agent-traces-YYYY.MM.DD (daily rolling)

Document schema:
  @timestamp, trace_id, session_id, question, route, tool_used,
  answer, latency_ms, model, chunks_retrieved, sql_query, sources
"""

from datetime import UTC, datetime
import logging
import uuid

from opensearchpy import OpenSearch

from app.config import settings
from app.state import AgentState

logger = logging.getLogger(__name__)

_os_client: OpenSearch | None = None


def get_opensearch() -> OpenSearch:
    global _os_client
    if _os_client is None:
        _os_client = OpenSearch(
            hosts=[
                {"host": settings.opensearch_host, "port": settings.opensearch_port}
            ],
            http_compress=True,
            use_ssl=False,
            verify_certs=False,
        )
    return _os_client


def write_trace(state: AgentState, latency_ms: float) -> str:
    """
    Write a trace document to OpenSearch. Returns the trace_id.
    Non-blocking: errors are logged but never raised.
    """
    trace_id = str(uuid.uuid4())
    today = datetime.now(UTC).strftime("%Y.%m.%d")
    index_name = f"{settings.opensearch_traces_index}-{today}"

    doc = {
        "@timestamp": datetime.now(UTC).isoformat(),
        "trace_id": trace_id,
        "session_id": state.get("session_id", "unknown"),
        "question": state.get("question", ""),
        "route": state.get("route", "unknown"),
        "tool_used": state.get("tool_used", "unknown"),
        "answer": state.get("answer", "")[:2000],  # cap at 2000 chars
        "latency_ms": latency_ms,
        "model": state.get("model", settings.agent_model),
        "chunks_retrieved": state.get("chunks_retrieved", 0),
        "sql_query": state.get("sql_query", ""),
        "sources": [
            {
                "filename": c.get("filename"),
                "score": c.get("score"),
            }
            for c in state.get("rag_chunks", [])
        ],
    }

    try:
        client = get_opensearch()
        client.index(index=index_name, body=doc)
        logger.debug("[Trace] Written to %s — trace_id: %s", index_name, trace_id)
    except Exception as exc:
        logger.warning("[Trace] Failed to write trace to OpenSearch: %s", exc)

    return trace_id
