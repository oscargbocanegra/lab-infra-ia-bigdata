"""
Router Node — decides which tool(s) to invoke.

Uses gemma3:4b with a structured prompt to classify the question:
- "rag"  → question about documents, policies, text content
- "data" → question about numbers, records, counts, SQL-able data
- "both" → needs both document context and structured data
"""

import logging

import httpx

from app.config import settings
from app.state import AgentState

logger = logging.getLogger(__name__)

ROUTER_PROMPT = """You are a routing assistant. Classify this question into ONE of three categories:

Categories:
- rag: Question is about documents, policies, text content, descriptions, or knowledge base items
- data: Question is about counts, statistics, records, numbers, or structured database data
- both: Question requires BOTH document knowledge AND structured data to answer

Rules:
- Respond with ONLY the category word: rag, data, or both
- No explanation, no punctuation, just the single word

Question: {question}

Category:"""


async def router_node(state: AgentState) -> dict:
    """
    Classify the question and decide which tools to invoke.
    Returns updated state with 'route' field set.
    """
    logger.info("[Router] Classifying question: %s", state["question"][:80])

    prompt = ROUTER_PROMPT.format(question=state["question"])

    async with httpx.AsyncClient(timeout=120.0) as client:
        resp = await client.post(
            f"{settings.ollama_base_url}/api/generate",
            json={
                "model": settings.agent_model,
                "prompt": prompt,
                "stream": False,
                "options": {"temperature": 0.0, "num_predict": 5},
            },
        )
        resp.raise_for_status()
        raw = resp.json()["response"].strip().lower()

    # Sanitize — only accept valid routes
    if "both" in raw:
        route = "both"
    elif "data" in raw:
        route = "data"
    else:
        route = "rag"  # default to RAG if unclear

    logger.info("[Router] Route decided: %s", route)
    return {"route": route}


def route_condition(state: AgentState) -> str:
    """
    LangGraph conditional edge function.
    Returns the name of the next node to execute.
    """
    route = state.get("route", "rag")
    if route == "both":
        return "both"
    elif route == "data":
        return "data"
    else:
        return "rag"
