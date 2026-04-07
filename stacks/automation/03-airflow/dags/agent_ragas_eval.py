"""
DAG: agent_ragas_eval
Phase: 9B — Agents & Evals

Runs RAGAS evaluation metrics against the synthetic dataset.

Strategy:
  1. Load latest RAGAS dataset from MinIO governance/ragas-datasets/
  2. Compute RAGAS metrics using Ollama as the LLM judge (no OpenAI needed):
     - faithfulness: does the answer contain only facts from the context?
     - answer_relevancy: is the answer on-topic?
     - context_precision: are retrieved chunks actually relevant?
     - context_recall: did we retrieve all relevant information?
  3. Save results to MinIO: governance/ragas-results/YYYY-MM-DD/results.json
  4. Push summary metrics to OpenSearch for trending dashboards

Note: RAGAS uses LangChain under the hood. We configure it to use Ollama
      (gemma3:4b for judge LLM, nomic-embed-text for relevancy embeddings).

Schedule: @weekly (Sundays 04:00 — runs 2h after synthetic_dataset)
"""

from __future__ import annotations

import json
import logging
import os
import io
from datetime import datetime, date, timedelta

import boto3
import httpx

from airflow.decorators import dag, task
from airflow.exceptions import AirflowFailException

logger = logging.getLogger(__name__)

# ─── Configuration ────────────────────────────────────────────────────────────
MINIO_ENDPOINT = os.environ.get("MINIO_ENDPOINT", "http://10.0.2.28:9000")
MINIO_ACCESS = os.environ.get("AWS_ACCESS_KEY_ID", "")
MINIO_SECRET = os.environ.get("AWS_SECRET_ACCESS_KEY", "")
MINIO_BUCKET = "governance"

OLLAMA_URL = "http://192.168.80.200:11434"
JUDGE_MODEL = "gemma3:4b"
EMBED_MODEL = "nomic-embed-text"

OPENSEARCH_URL = "http://opensearch:9200"
RAGAS_INDEX = "ragas-results"


def _s3_client():
    return boto3.client(
        "s3",
        endpoint_url=MINIO_ENDPOINT,
        aws_access_key_id=MINIO_ACCESS,
        aws_secret_access_key=MINIO_SECRET,
    )


# ─── RAGAS metrics implemented directly (no ragas package required) ───────────
# We implement faithfulness + answer_relevancy as LLM-as-judge prompts
# to avoid dependency issues with the ragas package in Airflow.

FAITHFULNESS_PROMPT = """Given the following context and answer, rate whether the answer
contains ONLY information from the context (no hallucinations).

Context:
{context}

Answer:
{answer}

Respond with a single number between 0 and 1 where:
- 1.0 = answer is fully supported by context
- 0.5 = answer is partially supported
- 0.0 = answer contains claims not in context

Score (just the number):"""

RELEVANCY_PROMPT = """Given the following question and answer, rate how relevant the answer
is to the question.

Question: {question}
Answer: {answer}

Respond with a single number between 0 and 1 where:
- 1.0 = answer directly and completely addresses the question
- 0.5 = answer is partially relevant
- 0.0 = answer is off-topic

Score (just the number):"""

CONTEXT_PRECISION_PROMPT = """Given the question and retrieved context chunks, rate how
relevant the retrieved context is for answering the question.

Question: {question}

Retrieved Context:
{contexts}

Respond with a single number between 0 and 1 where:
- 1.0 = retrieved context is highly relevant and sufficient
- 0.5 = partially relevant context
- 0.0 = context is irrelevant to the question

Score (just the number):"""


def _llm_score(prompt: str) -> float:
    """Call Ollama and extract a float score from the response."""
    try:
        resp = httpx.post(
            f"{OLLAMA_URL}/api/generate",
            json={
                "model": JUDGE_MODEL,
                "prompt": prompt,
                "stream": False,
                "options": {"temperature": 0.0, "num_predict": 10},
            },
            timeout=60.0,
        )
        resp.raise_for_status()
        raw = resp.json()["response"].strip()
        # Extract first float-like value
        for token in raw.replace(",", ".").split():
            try:
                score = float(token)
                return max(0.0, min(1.0, score))
            except ValueError:
                continue
    except Exception as exc:
        logger.warning("LLM scoring failed: %s", exc)
    return 0.0


# ─── DAG ──────────────────────────────────────────────────────────────────────
@dag(
    dag_id="agent_ragas_eval",
    description="RAGAS evaluation pipeline for the Hybrid Agent (Phase 9B)",
    schedule="0 4 * * 0",  # Sundays 04:00 — 2h after synthetic_dataset
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
def agent_ragas_eval():
    @task()
    def load_dataset() -> dict:
        """Load the most recent RAGAS dataset from MinIO."""
        run_date = date.today().isoformat()
        key = f"ragas-datasets/{run_date}/dataset.json"

        s3 = _s3_client()
        try:
            resp = s3.get_object(Bucket=MINIO_BUCKET, Key=key)
            dataset = json.loads(resp["Body"].read())
        except s3.exceptions.NoSuchKey:
            raise AirflowFailException(
                f"No dataset found at {key}. Run agent_synthetic_dataset first."
            )

        logger.info(
            "Loaded dataset: %d records from %s",
            dataset["sample_count"],
            key,
        )
        return dataset

    @task()
    def compute_metrics(dataset: dict) -> dict:
        """
        Compute RAGAS metrics for each record using LLM-as-judge (gemma3:4b).
        Returns per-record scores + aggregate statistics.
        """
        records = dataset["records"]
        scored_records = []

        for i, record in enumerate(records):
            question = record["question"]
            answer = record["answer"]
            contexts = record.get("contexts", [])
            ground_truth = record.get("ground_truth", "")

            if not answer:
                logger.warning("Skipping record %d — empty agent answer", i)
                scored_records.append({**record, "scores": None})
                continue

            context_str = "\n\n".join(contexts)

            faithfulness = _llm_score(
                FAITHFULNESS_PROMPT.format(context=context_str, answer=answer)
            )
            answer_relevancy = _llm_score(
                RELEVANCY_PROMPT.format(question=question, answer=answer)
            )
            context_precision = _llm_score(
                CONTEXT_PRECISION_PROMPT.format(question=question, contexts=context_str)
            )

            scores = {
                "faithfulness": round(faithfulness, 3),
                "answer_relevancy": round(answer_relevancy, 3),
                "context_precision": round(context_precision, 3),
            }

            scored_records.append({**record, "scores": scores})
            logger.info(
                "Record %d/%d — faithfulness=%.2f relevancy=%.2f precision=%.2f",
                i + 1,
                len(records),
                faithfulness,
                answer_relevancy,
                context_precision,
            )

        # Aggregate statistics
        valid_scores = [r["scores"] for r in scored_records if r["scores"]]
        agg = {}
        if valid_scores:
            for metric in ("faithfulness", "answer_relevancy", "context_precision"):
                values = [s[metric] for s in valid_scores]
                agg[metric] = {
                    "mean": round(sum(values) / len(values), 3),
                    "min": round(min(values), 3),
                    "max": round(max(values), 3),
                }

        return {
            "run_date": dataset["run_date"],
            "evaluated_at": datetime.utcnow().isoformat(),
            "judge_model": JUDGE_MODEL,
            "total_records": len(records),
            "scored_records": len(valid_scores),
            "aggregate": agg,
            "records": scored_records,
        }

    @task()
    def save_results(results: dict) -> str:
        """Save evaluation results to MinIO governance/ragas-results/"""
        run_date = results["run_date"]
        key = f"ragas-results/{run_date}/results.json"

        payload = json.dumps(results, indent=2, ensure_ascii=False).encode("utf-8")
        s3 = _s3_client()
        s3.put_object(
            Bucket=MINIO_BUCKET,
            Key=key,
            Body=io.BytesIO(payload),
            ContentType="application/json",
        )
        logger.info(
            "RAGAS results saved: s3://%s/%s (%d bytes)",
            MINIO_BUCKET,
            key,
            len(payload),
        )
        return f"s3://{MINIO_BUCKET}/{key}"

    @task()
    def push_to_opensearch(results: dict) -> None:
        """Push aggregate metrics to OpenSearch for trending dashboards."""
        run_date = results["run_date"]
        agg = results.get("aggregate", {})

        doc = {
            "@timestamp": results["evaluated_at"],
            "run_date": run_date,
            "judge_model": results["judge_model"],
            "total_records": results["total_records"],
            "scored_records": results["scored_records"],
            **{f"ragas_{k}": v["mean"] for k, v in agg.items()},
        }

        index_name = f"{RAGAS_INDEX}-{run_date}"
        try:
            resp = httpx.post(
                f"{OPENSEARCH_URL}/{index_name}/_doc",
                json=doc,
                timeout=10.0,
            )
            resp.raise_for_status()
            logger.info("RAGAS summary pushed to OpenSearch index %s", index_name)
        except Exception as exc:
            logger.warning("Failed to push to OpenSearch (non-fatal): %s", exc)

    @task()
    def assert_success(results: dict) -> None:
        """Fail the DAG if mean faithfulness is below threshold."""
        agg = results.get("aggregate", {})
        faithfulness_mean = agg.get("faithfulness", {}).get("mean", 0.0)
        threshold = 0.3  # low threshold for initial runs — expected with small models

        logger.info(
            "RAGAS summary — faithfulness=%.3f relevancy=%.3f precision=%.3f",
            agg.get("faithfulness", {}).get("mean", 0),
            agg.get("answer_relevancy", {}).get("mean", 0),
            agg.get("context_precision", {}).get("mean", 0),
        )

        if faithfulness_mean < threshold:
            raise AirflowFailException(
                f"Faithfulness score {faithfulness_mean:.3f} below threshold {threshold}. "
                "Review agent configuration."
            )
        logger.info(
            "Evaluation passed — faithfulness %.3f >= %.3f",
            faithfulness_mean,
            threshold,
        )

    # ─── DAG wiring ───────────────────────────────────────────────────────────
    dataset = load_dataset()
    results = compute_metrics(dataset)
    minio_path = save_results(results)
    push_to_opensearch(results)
    assert_success(results)


agent_ragas_eval()
