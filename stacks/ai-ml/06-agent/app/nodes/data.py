"""
Data Node — natural language → SQL → Postgres query.

Flow:
  1. Use qwen2.5-coder:7b to generate SQL from the question
  2. Execute SQL against the rag Postgres DB (read-only)
  3. Format result rows as context string

Safety: only SELECT statements are allowed — any other statement is rejected.
"""

import logging
import httpx
import asyncpg
from app.config import settings
from app.state import AgentState

logger = logging.getLogger(__name__)

# Schema context injected into the SQL generation prompt
# Describes the tables available in the rag DB
SCHEMA_CONTEXT = """
Available tables in the 'rag' database (PostgreSQL):

documents (
    id          SERIAL PRIMARY KEY,
    collection  TEXT,           -- logical collection name (e.g. 'default', 'sales')
    filename    TEXT,           -- original filename
    source_url  TEXT,           -- MinIO path
    chunk_index INTEGER,        -- chunk position within the document
    chunk_text  TEXT,           -- raw chunk content
    token_count INTEGER,        -- approximate word count
    model       TEXT,           -- embedding model used
    metadata    JSONB,          -- arbitrary metadata
    created_at  TIMESTAMP DEFAULT NOW()
)

embeddings (
    id          SERIAL PRIMARY KEY,
    document_id INTEGER REFERENCES documents(id),
    embedding   vector(768)     -- pgvector embedding
)

Note: for performance, always add WHERE or LIMIT clauses. Never SELECT * without LIMIT.
"""

SQL_GENERATION_PROMPT = """You are a PostgreSQL expert. Generate a single SQL SELECT query based on the question.

{schema}

Rules:
- Generate ONLY a SQL SELECT query
- No markdown, no explanation, no comments
- End with semicolon
- Maximum 100 rows (add LIMIT if needed)
- Never use INSERT, UPDATE, DELETE, DROP, CREATE, or any DDL

Question: {question}

SQL:"""


async def data_node(state: AgentState) -> dict:
    """
    Generate SQL from question and execute against Postgres.
    Returns query result as context string.
    """
    question = state["question"]
    logger.info("[Data] Generating SQL for question: %s", question[:80])

    # 1. Generate SQL with qwen2.5-coder
    prompt = SQL_GENERATION_PROMPT.format(schema=SCHEMA_CONTEXT, question=question)

    async with httpx.AsyncClient(timeout=60.0) as client:
        resp = await client.post(
            f"{settings.ollama_base_url}/api/generate",
            json={
                "model": settings.coder_model,
                "prompt": prompt,
                "stream": False,
                "options": {"temperature": 0.0, "num_predict": 256},
            },
        )
        resp.raise_for_status()
        raw_sql = resp.json()["response"].strip()

    # Clean up potential markdown code fences
    sql_query = raw_sql
    for fence in ["```sql", "```", "SQL:", "sql:"]:
        sql_query = sql_query.replace(fence, "").strip()

    logger.info("[Data] Generated SQL: %s", sql_query[:200])

    # 2. Safety check — only SELECT allowed
    sql_upper = sql_query.upper().lstrip()
    if not sql_upper.startswith("SELECT"):
        logger.warning("[Data] Rejected non-SELECT query: %s", sql_query[:100])
        return {
            "sql_query": sql_query,
            "sql_result": [],
            "data_context": "Query rejected — only SELECT statements are allowed for safety.",
        }

    # 3. Execute against Postgres
    try:
        conn = await asyncpg.connect(
            host=settings.pg_host,
            port=settings.pg_port,
            database=settings.pg_db,
            user=settings.pg_user,
            password=settings.pg_password,
        )
        try:
            rows = await conn.fetch(sql_query)
            result_rows = [dict(r) for r in rows]
            logger.info("[Data] Query returned %d rows", len(result_rows))
        finally:
            await conn.close()
    except Exception as exc:
        logger.error("[Data] SQL execution error: %s", exc)
        return {
            "sql_query": sql_query,
            "sql_result": [],
            "data_context": f"SQL execution failed: {exc}",
        }

    # 4. Format result as context
    if not result_rows:
        data_context = "Query executed successfully but returned no rows."
    else:
        # Build a simple table representation
        if result_rows:
            headers = list(result_rows[0].keys())
            header_line = " | ".join(headers)
            separator = "-" * len(header_line)
            rows_lines = [
                " | ".join(str(row.get(h, "")) for h in headers)
                for row in result_rows[:50]  # cap at 50 rows in context
            ]
            data_context = (
                f"SQL Result ({len(result_rows)} rows):\n{header_line}\n{separator}\n"
                + "\n".join(rows_lines)
            )
            if len(result_rows) > 50:
                data_context += f"\n... ({len(result_rows) - 50} more rows truncated)"
        else:
            data_context = "No results."

    return {
        "sql_query": sql_query,
        "sql_result": result_rows[:50],  # cap for state size
        "data_context": data_context,
    }
