"""
Lab Hybrid Agent API — Main entrypoint

Endpoints:
  POST /agent/query   — run the hybrid LangGraph agent
  GET  /health        — liveness probe
"""

from contextlib import asynccontextmanager
import logging
import time
import uuid

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

from app.config import settings
from app.graph import get_graph
from app.tracing import write_trace

logging.basicConfig(
    level=getattr(logging, settings.log_level),
    format="%(asctime)s [%(levelname)s] %(name)s — %(message)s",
)
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("Starting Hybrid Agent API — compiling LangGraph...")
    get_graph()  # compile once at startup
    logger.info("Agent ready.")
    yield
    logger.info("Shutting down Hybrid Agent API.")


app = FastAPI(
    title=settings.api_title,
    version=settings.api_version,
    description=(
        "Hybrid LangGraph Agent — routes questions to RAG (Qdrant) or "
        "Data (Postgres SQL) tools based on intent, then synthesizes the answer."
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


# ─── Request / Response models ───────────────────────────────────────────────


class AgentQueryRequest(BaseModel):
    question: str
    session_id: str | None = None


class SourceChunk(BaseModel):
    filename: str
    score: float


class AgentQueryResponse(BaseModel):
    trace_id: str
    session_id: str
    question: str
    answer: str
    route: str  # rag | data | both
    tool_used: str
    model: str
    latency_ms: float
    chunks_retrieved: int
    sources: list[SourceChunk]
    sql_query: str | None = None


# ─── Endpoints ───────────────────────────────────────────────────────────────


@app.get("/health")
async def health():
    return {"status": "ok", "version": settings.api_version}


@app.post("/agent/query", response_model=AgentQueryResponse)
async def agent_query(req: AgentQueryRequest):
    """
    Run the hybrid LangGraph agent.

    The agent:
    1. Routes the question: RAG / Data / Both
    2. Executes the appropriate tool(s) in parallel if needed
    3. Synthesizes a final answer using gemma3:4b
    4. Writes a trace to OpenSearch for observability

    - **question**: the user's question
    - **session_id**: optional session identifier for grouping traces
    """
    session_id = req.session_id or str(uuid.uuid4())
    start_ts = time.perf_counter()

    # Initial state
    initial_state = {
        "question": req.question,
        "session_id": session_id,
        "route": "",
        "rag_chunks": [],
        "rag_context": "",
        "sql_query": "",
        "sql_result": [],
        "data_context": "",
        "answer": "",
        "tool_used": "",
        "latency_ms": 0.0,
        "model": settings.agent_model,
        "chunks_retrieved": 0,
    }

    # Run the graph
    graph = get_graph()
    final_state = await graph.ainvoke(initial_state)

    latency_ms = round((time.perf_counter() - start_ts) * 1000, 1)
    final_state["latency_ms"] = latency_ms

    # Write trace to OpenSearch (best-effort)
    trace_id = write_trace(final_state, latency_ms)

    logger.info(
        "Agent query completed — route=%s latency=%.0fms trace=%s",
        final_state.get("route"),
        latency_ms,
        trace_id,
    )

    return AgentQueryResponse(
        trace_id=trace_id,
        session_id=session_id,
        question=req.question,
        answer=final_state.get("answer", ""),
        route=final_state.get("route", "unknown"),
        tool_used=final_state.get("tool_used", "unknown"),
        model=final_state.get("model", settings.agent_model),
        latency_ms=latency_ms,
        chunks_retrieved=final_state.get("chunks_retrieved", 0),
        sources=[
            SourceChunk(filename=c["filename"], score=c["score"])
            for c in final_state.get("rag_chunks", [])
        ],
        sql_query=final_state.get("sql_query") or None,
    )
