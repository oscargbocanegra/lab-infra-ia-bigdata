"""
LangGraph agent graph definition — Hybrid RAG + Data Agent.

Graph structure:
  START → router → {rag, data, both_rag+data} → synthesizer → trace_writer → END

For "both" route, RAG and Data nodes run in parallel (LangGraph fan-out).
"""

import asyncio
import logging
from langgraph.graph import StateGraph, START, END

from app.state import AgentState
from app.nodes.router import router_node, route_condition
from app.nodes.rag import rag_node
from app.nodes.data import data_node
from app.nodes.synthesizer import synthesizer_node

logger = logging.getLogger(__name__)


async def both_node(state: AgentState) -> dict:
    """
    Fan-out node: runs RAG and Data in parallel for 'both' route.
    Returns merged state from both tools.
    """
    logger.info("[Both] Running RAG + Data in parallel")
    rag_result, data_result = await asyncio.gather(
        rag_node(state),
        data_node(state),
    )
    # Merge both results — no key conflicts since RAG and Data use different keys
    merged = {}
    merged.update(rag_result)
    merged.update(data_result)
    return merged


def build_graph() -> StateGraph:
    """
    Construct and compile the LangGraph StateGraph.

    Nodes:
      - router:      classifies the question → sets state.route
      - rag:         semantic search in Qdrant → sets rag_chunks, rag_context
      - data:        SQL generation + Postgres query → sets sql_query, sql_result, data_context
      - both:        parallel execution of rag + data
      - synthesizer: generates final answer from context
    """
    graph = StateGraph(AgentState)

    # Add nodes
    graph.add_node("router", router_node)
    graph.add_node("rag", rag_node)
    graph.add_node("data", data_node)
    graph.add_node("both", both_node)
    graph.add_node("synthesizer", synthesizer_node)

    # Entry: START → router
    graph.add_edge(START, "router")

    # Conditional: router → rag | data | both
    graph.add_conditional_edges(
        "router",
        route_condition,
        {
            "rag": "rag",
            "data": "data",
            "both": "both",
        },
    )

    # All tool nodes → synthesizer
    graph.add_edge("rag", "synthesizer")
    graph.add_edge("data", "synthesizer")
    graph.add_edge("both", "synthesizer")

    # synthesizer → END
    graph.add_edge("synthesizer", END)

    return graph.compile()


# Singleton compiled graph — built once at startup
_compiled_graph = None


def get_graph():
    global _compiled_graph
    if _compiled_graph is None:
        _compiled_graph = build_graph()
        logger.info("LangGraph agent compiled successfully")
    return _compiled_graph
