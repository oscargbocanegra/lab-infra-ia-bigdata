"""
DAG: agent_synthetic_dataset
Phase: 9B — Agents & Evals

Generates a synthetic Q&A dataset for RAGAS evaluation.

Strategy:
  1. Fetch a sample of indexed document chunks from Postgres (rag DB)
  2. Use gemma3:4b via Ollama to generate question + ground_truth answer for each chunk
  3. Call the Hybrid Agent API to get the actual agent answer + retrieved contexts
  4. Save the RAGAS-compatible dataset to MinIO: governance/ragas-datasets/YYYY-MM-DD/dataset.json

RAGAS dataset format:
  {
    "question": "...",
    "answer": "...",          <- agent's actual answer
    "contexts": ["..."],      <- chunks retrieved by agent
    "ground_truth": "..."     <- gemma3:4b generated ground truth
  }

Schedule: @weekly (Sundays 02:00)
"""

from __future__ import annotations

import json
import logging
import os
import io
from datetime import datetime, date, timedelta

import boto3
import httpx
import psycopg2
import psycopg2.extras

from airflow.decorators import dag, task
from airflow.exceptions import AirflowFailException

logger = logging.getLogger(__name__)

# ─── Configuration ────────────────────────────────────────────────────────────
MINIO_ENDPOINT = os.environ.get("MINIO_ENDPOINT", "http://10.0.2.28:9000")
MINIO_ACCESS = os.environ.get("AWS_ACCESS_KEY_ID", "")
MINIO_SECRET = os.environ.get("AWS_SECRET_ACCESS_KEY", "")
MINIO_BUCKET = "governance"

OLLAMA_URL = os.environ.get(
    "OLLAMA_BASE_URL", "http://ollama:11434"
)  # Docker overlay DNS
AGENT_URL = "http://agent:8000"  # internal overlay
GENERATOR_MODEL = "gemma3:4b"

PG_HOST = os.environ.get("PG_RAG_HOST", "postgres")  # Docker overlay DNS
PG_PORT = 5432
PG_DB = "rag"
PG_USER = "rag"
PG_PASSWORD = os.environ.get("PG_RAG_PASS", "")

SAMPLES_PER_RUN = 10  # number of Q&A pairs to generate per run


# ─── Prompts ──────────────────────────────────────────────────────────────────
QUESTION_GEN_PROMPT = """Based on the following document chunk, generate ONE specific, answerable question.

Rules:
- Generate only the question, nothing else
- The question must be answerable from the chunk content
- Be specific, not generic

Chunk:
{chunk}

Question:"""

GROUND_TRUTH_PROMPT = """Answer the following question based ONLY on the provided context.
Be concise and accurate.

Context:
{chunk}

Question: {question}

Answer:"""


# ─── DAG ──────────────────────────────────────────────────────────────────────
@dag(
    dag_id="agent_synthetic_dataset",
    description="Generate synthetic Q&A dataset for RAGAS evaluation (Phase 9B)",
    schedule="0 2 * * 0",  # Sundays 02:00
    start_date=datetime(2026, 4, 1),
    catchup=False,
    max_active_runs=1,
    tags=["phase-9b", "agents", "ragas", "evaluation"],
    default_args={
        "owner": "airflow",
        "retries": 1,
        "retry_delay": timedelta(minutes=5),
    },
)
def agent_synthetic_dataset():
    @task()
    def fetch_sample_chunks() -> list[dict]:
        """Fetch a random sample of document chunks from Postgres rag DB."""
        conn = psycopg2.connect(
            host=PG_HOST,
            port=PG_PORT,
            dbname=PG_DB,
            user=PG_USER,
            password=PG_PASSWORD,
        )
        try:
            with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
                cur.execute(
                    """
                    SELECT id, collection, filename, chunk_index, chunk_text
                    FROM documents
                    WHERE char_length(chunk_text) > 100
                    ORDER BY RANDOM()
                    LIMIT %s
                    """,
                    (SAMPLES_PER_RUN,),
                )
                rows = cur.fetchall()
        finally:
            conn.close()

        chunks = [dict(r) for r in rows]
        logger.info("Fetched %d sample chunks from Postgres", len(chunks))

        if not chunks:
            raise AirflowFailException(
                "No document chunks found in Postgres. "
                "Ingest documents via the RAG API first."
            )
        return chunks

    @task()
    def generate_qa_pairs(chunks: list[dict]) -> list[dict]:
        """Generate question + ground_truth for each chunk using gemma3:4b."""
        qa_pairs = []

        for chunk in chunks:
            chunk_text = chunk["chunk_text"]

            # Generate question
            q_resp = httpx.post(
                f"{OLLAMA_URL}/api/generate",
                json={
                    "model": GENERATOR_MODEL,
                    "prompt": QUESTION_GEN_PROMPT.format(chunk=chunk_text),
                    "stream": False,
                    "options": {"temperature": 0.7, "num_predict": 64},
                },
                timeout=180.0,  # 3min — gemma3:4b cold start can take >60s
            )
            q_resp.raise_for_status()
            question = q_resp.json()["response"].strip()

            # Generate ground truth answer
            gt_resp = httpx.post(
                f"{OLLAMA_URL}/api/generate",
                json={
                    "model": GENERATOR_MODEL,
                    "prompt": GROUND_TRUTH_PROMPT.format(
                        chunk=chunk_text, question=question
                    ),
                    "stream": False,
                    "options": {"temperature": 0.1, "num_predict": 256},
                },
                timeout=180.0,  # 3min — gemma3:4b cold start can take >60s
            )
            gt_resp.raise_for_status()
            ground_truth = gt_resp.json()["response"].strip()

            qa_pairs.append(
                {
                    "chunk_id": chunk["id"],
                    "collection": chunk["collection"],
                    "filename": chunk["filename"],
                    "chunk_index": chunk["chunk_index"],
                    "chunk_text": chunk_text,
                    "question": question,
                    "ground_truth": ground_truth,
                }
            )
            logger.info("Generated Q&A for chunk %s: %s", chunk["id"], question[:60])

        return qa_pairs

    @task()
    def run_agent_queries(qa_pairs: list[dict]) -> list[dict]:
        """
        Run each question through the Hybrid Agent to get actual answers + contexts.
        This creates the full RAGAS-compatible record.
        """
        ragas_records = []

        for item in qa_pairs:
            try:
                resp = httpx.post(
                    f"{AGENT_URL}/agent/query",
                    json={
                        "question": item["question"],
                        "session_id": f"ragas-synthetic-{date.today().isoformat()}",
                    },
                    timeout=120.0,
                )
                resp.raise_for_status()
                agent_resp = resp.json()

                ragas_records.append(
                    {
                        "question": item["question"],
                        "answer": agent_resp["answer"],
                        "contexts": [
                            s["filename"] + ": " + item["chunk_text"]
                            for s in agent_resp.get("sources", [])
                        ]
                        or [item["chunk_text"]],
                        "ground_truth": item["ground_truth"],
                        # Metadata (not used by RAGAS but useful for debugging)
                        "_meta": {
                            "chunk_id": item["chunk_id"],
                            "filename": item["filename"],
                            "route": agent_resp.get("route"),
                            "latency_ms": agent_resp.get("latency_ms"),
                            "trace_id": agent_resp.get("trace_id"),
                        },
                    }
                )
                logger.info(
                    "Agent answered question '%s...' in %.0fms",
                    item["question"][:40],
                    agent_resp.get("latency_ms", 0),
                )
            except Exception as exc:
                logger.warning(
                    "Agent query failed for question '%s': %s",
                    item["question"][:40],
                    exc,
                )
                # Keep partial record without agent answer
                ragas_records.append(
                    {
                        "question": item["question"],
                        "answer": "",
                        "contexts": [item["chunk_text"]],
                        "ground_truth": item["ground_truth"],
                        "_meta": {"chunk_id": item["chunk_id"], "error": str(exc)},
                    }
                )

        return ragas_records

    @task()
    def save_dataset(ragas_records: list[dict]) -> str:
        """Save RAGAS dataset to MinIO governance/ragas-datasets/YYYY-MM-DD/dataset.json"""
        run_date = date.today().isoformat()
        minio_key = f"ragas-datasets/{run_date}/dataset.json"

        dataset = {
            "generated_at": datetime.utcnow().isoformat(),
            "run_date": run_date,
            "model": GENERATOR_MODEL,
            "sample_count": len(ragas_records),
            "records": ragas_records,
        }

        payload = json.dumps(dataset, indent=2, ensure_ascii=False).encode("utf-8")

        s3 = boto3.client(
            "s3",
            endpoint_url=MINIO_ENDPOINT,
            aws_access_key_id=MINIO_ACCESS,
            aws_secret_access_key=MINIO_SECRET,
        )
        s3.put_object(
            Bucket=MINIO_BUCKET,
            Key=minio_key,
            Body=io.BytesIO(payload),
            ContentType="application/json",
        )

        logger.info(
            "RAGAS dataset saved: s3://%s/%s (%d records, %d bytes)",
            MINIO_BUCKET,
            minio_key,
            len(ragas_records),
            len(payload),
        )
        return f"s3://{MINIO_BUCKET}/{minio_key}"

    @task()
    def assert_dataset_saved(minio_path: str) -> None:
        """Verify the dataset was saved to MinIO."""
        parts = minio_path.replace("s3://", "").split("/", 1)
        bucket, key = parts[0], parts[1]

        s3 = boto3.client(
            "s3",
            endpoint_url=MINIO_ENDPOINT,
            aws_access_key_id=MINIO_ACCESS,
            aws_secret_access_key=MINIO_SECRET,
        )
        resp = s3.head_object(Bucket=bucket, Key=key)
        size = resp["ContentLength"]

        if size < 10:
            raise AirflowFailException(f"Dataset file too small: {size} bytes")

        logger.info("Dataset verified: %s (%d bytes)", minio_path, size)

    # ─── DAG wiring ───────────────────────────────────────────────────────────
    chunks = fetch_sample_chunks()
    qa_pairs = generate_qa_pairs(chunks)
    ragas_records = run_agent_queries(qa_pairs)
    minio_path = save_dataset(ragas_records)
    assert_dataset_saved(minio_path)


agent_synthetic_dataset()
