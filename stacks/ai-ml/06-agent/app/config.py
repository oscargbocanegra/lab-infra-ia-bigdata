"""Configuration — reads from environment variables and Docker secret files."""

from pathlib import Path

from pydantic_settings import BaseSettings


def _read_secret(path: str) -> str:
    p = Path(path)
    if p.exists():
        return p.read_text().strip()
    return ""


class Settings(BaseSettings):
    # Ollama — GPU inference on master2
    ollama_base_url: str = "http://192.168.80.200:11434"
    agent_model: str = "gemma3:4b"  # primary reasoning
    coder_model: str = "qwen2.5-coder:7b"  # SQL generation
    embed_model: str = "nomic-embed-text"
    embed_dims: int = 768

    # Qdrant — vector store on master1 (internal overlay)
    qdrant_url: str = "http://qdrant:6333"
    qdrant_api_key_file: str = "/run/secrets/qdrant_api_key"
    qdrant_collection: str = "lab_documents_nomic"

    # Postgres — rag DB on master2
    pg_host: str = "192.168.80.200"
    pg_port: int = 5432
    pg_db: str = "rag"
    pg_user: str = "rag"
    pg_password_file: str = "/run/secrets/pg_rag_pass"

    # OpenSearch — trace storage
    opensearch_host: str = "opensearch"
    opensearch_port: int = 9200
    opensearch_traces_index: str = "agent-traces"

    # RAG parameters
    top_k: int = 5

    # API
    api_title: str = "Lab Hybrid Agent API"
    api_version: str = "1.0.0"
    log_level: str = "INFO"

    @property
    def qdrant_api_key(self) -> str:
        return _read_secret(self.qdrant_api_key_file)

    @property
    def pg_password(self) -> str:
        return _read_secret(self.pg_password_file)

    @property
    def pg_dsn_async(self) -> str:
        return (
            f"postgresql+asyncpg://{self.pg_user}:{self.pg_password}"
            f"@{self.pg_host}:{self.pg_port}/{self.pg_db}"
        )

    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"


settings = Settings()
