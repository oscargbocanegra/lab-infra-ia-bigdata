"""
DAG: agent_model_benchmark
Phase: 9B — Agents & Evals

Benchmarks all available Ollama models against a curated question set.

Categories:
  1. instruction_following — basic Q&A, format compliance (5 questions)
  2. reasoning            — multi-step logic problems (5 questions)
  3. coding               — Python/SQL generation (5 questions)

Each model answers all 15 questions. Responses are scored by gemma3:4b
as an LLM judge (0-1 scale per question).

Results saved to MinIO: governance/benchmarks/YYYY-MM-DD/results.json

Models tested: all models returned by Ollama /api/tags endpoint
  - gemma3:4b
  - qwen2.5-coder:7b
  - qwen3.5:latest
  (embedding models bge-m3, nomic-embed-text are skipped)

Schedule: @weekly (Sundays 06:00)
"""

from __future__ import annotations

import json
import logging
import os
import io
import time
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

OLLAMA_URL = os.environ.get(
    "OLLAMA_BASE_URL", "http://ollama:11434"
)  # Docker overlay DNS
JUDGE_MODEL = "gemma3:4b"

# Skip these — they are embedding models, not instruction-following
SKIP_MODELS = {"nomic-embed-text:latest", "bge-m3:latest"}

# ─── Benchmark question set ───────────────────────────────────────────────────
BENCHMARK_QUESTIONS = [
    # Category: instruction_following
    {
        "id": "if_01",
        "category": "instruction_following",
        "question": "List 3 programming languages and their primary use cases. Format as a numbered list.",
        "expected_format": "numbered list with 3 items",
    },
    {
        "id": "if_02",
        "category": "instruction_following",
        "question": "What is the capital of France? Answer in exactly one word.",
        "expected_format": "single word",
    },
    {
        "id": "if_03",
        "category": "instruction_following",
        "question": "Summarize the concept of REST API in 2 sentences maximum.",
        "expected_format": "2 sentences max",
    },
    {
        "id": "if_04",
        "category": "instruction_following",
        "question": "Convert this temperature: 100 Celsius to Fahrenheit. Show only the numeric result.",
        "expected_format": "numeric result",
    },
    {
        "id": "if_05",
        "category": "instruction_following",
        "question": "Respond with only 'yes' or 'no': Is Python a compiled language?",
        "expected_format": "yes or no",
    },
    # Category: reasoning
    {
        "id": "r_01",
        "category": "reasoning",
        "question": "If a train travels 120 km in 2 hours, then increases speed by 50%, how long will it take to travel the next 180 km?",
        "expected_format": "numeric answer with explanation",
    },
    {
        "id": "r_02",
        "category": "reasoning",
        "question": "Alice has 3 cats. Bob has twice as many cats as Alice. Carol has 5 fewer cats than Bob. How many cats does Carol have?",
        "expected_format": "numeric answer",
    },
    {
        "id": "r_03",
        "category": "reasoning",
        "question": "A Docker container is to a VM as a process is to ___. Explain why.",
        "expected_format": "analogy with explanation",
    },
    {
        "id": "r_04",
        "category": "reasoning",
        "question": "You have a sorted list of 1 million integers. Which search algorithm would you use and why?",
        "expected_format": "algorithm name with justification",
    },
    {
        "id": "r_05",
        "category": "reasoning",
        "question": "If all Blorks are Flerps, and some Flerps are Glorps, can we conclude that some Blorks are Glorps? Explain.",
        "expected_format": "yes/no with logical reasoning",
    },
    # Category: coding
    {
        "id": "c_01",
        "category": "coding",
        "question": "Write a Python function that takes a list of integers and returns the second largest unique number.",
        "expected_format": "Python function",
    },
    {
        "id": "c_02",
        "category": "coding",
        "question": "Write a SQL query to find the top 3 customers by total purchase amount from a table called 'orders' with columns: customer_id, amount, created_at.",
        "expected_format": "SQL SELECT query",
    },
    {
        "id": "c_03",
        "category": "coding",
        "question": "Write a Python decorator that logs the execution time of any function.",
        "expected_format": "Python decorator",
    },
    {
        "id": "c_04",
        "category": "coding",
        "question": "What does this Python code do? Explain line by line: [x**2 for x in range(10) if x % 2 == 0]",
        "expected_format": "line-by-line explanation",
    },
    {
        "id": "c_05",
        "category": "coding",
        "question": "Write a SQL query using a window function to calculate the running total of sales by date from a 'sales' table with columns: sale_date, amount.",
        "expected_format": "SQL query with window function",
    },
]

JUDGE_PROMPT = """Rate the quality of this AI response to the question.

Question: {question}
Expected format: {expected_format}
Response: {response}

Rate on a scale from 0 to 1:
- 1.0: Excellent — correct, well-formatted, fully addresses the question
- 0.7: Good — correct but minor formatting issues
- 0.5: Acceptable — partially correct or off-format
- 0.3: Poor — mostly incorrect or missing key elements
- 0.0: Completely wrong or no response

Respond with ONLY a decimal number (e.g. 0.8):"""


def _s3_client():
    return boto3.client(
        "s3",
        endpoint_url=MINIO_ENDPOINT,
        aws_access_key_id=MINIO_ACCESS,
        aws_secret_access_key=MINIO_SECRET,
    )


def _judge_response(question: str, expected_format: str, response: str) -> float:
    """Use JUDGE_MODEL to score a response. Returns 0.0-1.0."""
    try:
        resp = httpx.post(
            f"{OLLAMA_URL}/api/generate",
            json={
                "model": JUDGE_MODEL,
                "prompt": JUDGE_PROMPT.format(
                    question=question,
                    expected_format=expected_format,
                    response=response[:500],  # cap for judge context
                ),
                "stream": False,
                "options": {"temperature": 0.0, "num_predict": 10},
            },
            timeout=180.0,  # 3min — gemma3:4b cold start can take >60s
        )
        resp.raise_for_status()
        raw = resp.json()["response"].strip()
        for token in raw.replace(",", ".").split():
            try:
                return max(0.0, min(1.0, float(token)))
            except ValueError:
                continue
    except Exception as exc:
        logger.warning("Judge call failed: %s", exc)
    return 0.0


# ─── DAG ──────────────────────────────────────────────────────────────────────
@dag(
    dag_id="agent_model_benchmark",
    description="Benchmark all Ollama models against curated question set (Phase 9B)",
    schedule="0 6 * * 0",  # Sundays 06:00
    start_date=datetime(2026, 4, 1),
    catchup=False,
    max_active_runs=1,
    tags=["phase-9b", "agents", "benchmark", "evaluation"],
    default_args={
        "owner": "airflow",
        "retries": 1,
        "retry_delay": timedelta(minutes=5),
    },
)
def agent_model_benchmark():
    @task()
    def get_available_models() -> list[str]:
        """Fetch list of models from Ollama API."""
        resp = httpx.get(f"{OLLAMA_URL}/api/tags", timeout=10.0)
        resp.raise_for_status()
        all_models = [m["name"] for m in resp.json().get("models", [])]
        models = [m for m in all_models if m not in SKIP_MODELS]
        logger.info("Available models for benchmarking: %s", models)
        if not models:
            raise AirflowFailException("No models available in Ollama for benchmarking")
        return models

    @task()
    def run_benchmarks(models: list[str]) -> list[dict]:
        """
        Run all benchmark questions against all models.
        Returns list of per-model results.
        """
        all_results = []

        for model in models:
            logger.info("Benchmarking model: %s", model)
            model_results = {
                "model": model,
                "run_date": date.today().isoformat(),
                "questions": [],
                "scores_by_category": {},
            }

            for q in BENCHMARK_QUESTIONS:
                start = time.perf_counter()
                try:
                    resp = httpx.post(
                        f"{OLLAMA_URL}/api/generate",
                        json={
                            "model": model,
                            "prompt": q["question"],
                            "stream": False,
                            "options": {"temperature": 0.1, "num_predict": 512},
                        },
                        timeout=120.0,
                    )
                    resp.raise_for_status()
                    response_text = resp.json()["response"].strip()
                    latency_ms = round((time.perf_counter() - start) * 1000, 1)
                except Exception as exc:
                    logger.warning("Model %s failed on %s: %s", model, q["id"], exc)
                    response_text = ""
                    latency_ms = 0.0

                # Judge the response
                score = (
                    _judge_response(q["question"], q["expected_format"], response_text)
                    if response_text
                    else 0.0
                )

                model_results["questions"].append(
                    {
                        "id": q["id"],
                        "category": q["category"],
                        "question": q["question"],
                        "response": response_text[:500],
                        "score": round(score, 3),
                        "latency_ms": latency_ms,
                    }
                )
                logger.info(
                    "  %s — %s: score=%.2f latency=%.0fms",
                    model,
                    q["id"],
                    score,
                    latency_ms,
                )

            # Aggregate by category
            by_category: dict[str, list[float]] = {}
            for item in model_results["questions"]:
                cat = item["category"]
                by_category.setdefault(cat, []).append(item["score"])

            model_results["scores_by_category"] = {
                cat: round(sum(scores) / len(scores), 3)
                for cat, scores in by_category.items()
            }
            all_scores = [q["score"] for q in model_results["questions"]]
            model_results["overall_score"] = (
                round(sum(all_scores) / len(all_scores), 3) if all_scores else 0.0
            )

            logger.info(
                "Model %s overall score: %.3f",
                model,
                model_results["overall_score"],
            )
            all_results.append(model_results)

        return all_results

    @task()
    def save_benchmark_results(results: list[dict]) -> str:
        """Save benchmark results to MinIO governance/benchmarks/"""
        run_date = date.today().isoformat()
        key = f"benchmarks/{run_date}/results.json"

        output = {
            "run_date": run_date,
            "benchmarked_at": datetime.utcnow().isoformat(),
            "judge_model": JUDGE_MODEL,
            "total_questions": len(BENCHMARK_QUESTIONS),
            "models_tested": len(results),
            "results": results,
            # Leaderboard summary
            "leaderboard": sorted(
                [
                    {"model": r["model"], "overall_score": r["overall_score"]}
                    for r in results
                ],
                key=lambda x: x["overall_score"],
                reverse=True,
            ),
        }

        payload = json.dumps(output, indent=2, ensure_ascii=False).encode("utf-8")
        s3 = _s3_client()
        s3.put_object(
            Bucket=MINIO_BUCKET,
            Key=key,
            Body=io.BytesIO(payload),
            ContentType="application/json",
        )
        logger.info(
            "Benchmark results saved: s3://%s/%s",
            MINIO_BUCKET,
            key,
        )

        # Log leaderboard
        for rank, entry in enumerate(output["leaderboard"], 1):
            logger.info(
                "  #%d %s — %.3f",
                rank,
                entry["model"],
                entry["overall_score"],
            )

        return f"s3://{MINIO_BUCKET}/{key}"

    @task()
    def push_leaderboard_to_opensearch(results: list[dict]) -> None:
        """Push per-model scores to OpenSearch for Grafana trending."""
        run_date = date.today().isoformat()
        index_name = f"model-benchmarks-{run_date}"

        for result in results:
            doc = {
                "@timestamp": datetime.utcnow().isoformat(),
                "run_date": run_date,
                "model": result["model"],
                "overall_score": result["overall_score"],
                **{
                    f"score_{cat}": score
                    for cat, score in result["scores_by_category"].items()
                },
            }
            try:
                resp = httpx.post(
                    f"http://opensearch:9200/{index_name}/_doc",
                    json=doc,
                    timeout=10.0,
                )
                resp.raise_for_status()
            except Exception as exc:
                logger.warning("Failed to push benchmark to OpenSearch: %s", exc)

        logger.info("Benchmark leaderboard pushed to OpenSearch index %s", index_name)

    # ─── DAG wiring ───────────────────────────────────────────────────────────
    models = get_available_models()
    results = run_benchmarks(models)
    minio_path = save_benchmark_results(results)
    push_leaderboard_to_opensearch(results)


agent_model_benchmark()
