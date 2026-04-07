"""
Synthesizer Node — final answer generation.

Combines all gathered context (RAG chunks + SQL results) into a single
coherent answer using gemma3:4b.

This is the last LLM call before the answer is returned to the user.
"""

import logging
import httpx
from app.config import settings
from app.state import AgentState

logger = logging.getLogger(__name__)

SYNTHESIZER_PROMPT = """You are a helpful AI assistant. Answer the question using the provided context.

Rules:
- Be concise and accurate
- If context is insufficient, say so honestly
- Cite document sources when using RAG context (e.g. "[Source: filename.pdf, chunk 2]")
- Format numbers clearly when using data results
- Never make up information not present in the context

{rag_section}
{data_section}

QUESTION: {question}

ANSWER:"""


async def synthesizer_node(state: AgentState) -> dict:
    """
    Generate final answer by combining all available context.
    """
    question = state["question"]
    route = state.get("route", "rag")

    # Build context sections based on what tools were used
    rag_section = ""
    data_section = ""

    if route in ("rag", "both") and state.get("rag_context"):
        rag_section = f"DOCUMENT CONTEXT:\n{state['rag_context']}\n"

    if route in ("data", "both") and state.get("data_context"):
        data_section = f"DATA CONTEXT:\n{state['data_context']}\n"

    prompt = SYNTHESIZER_PROMPT.format(
        rag_section=rag_section,
        data_section=data_section,
        question=question,
    )

    logger.info("[Synthesizer] Generating final answer (route=%s)", route)

    async with httpx.AsyncClient(timeout=120.0) as client:
        resp = await client.post(
            f"{settings.ollama_base_url}/api/generate",
            json={
                "model": settings.agent_model,
                "prompt": prompt,
                "stream": False,
                "options": {"temperature": 0.3, "num_predict": 1024},
            },
        )
        resp.raise_for_status()
        answer = resp.json()["response"].strip()

    logger.info("[Synthesizer] Answer generated (%d chars)", len(answer))

    return {
        "answer": answer,
        "model": settings.agent_model,
        "tool_used": route,
    }
