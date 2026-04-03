"""Configuration — reads from environment variables and secret files."""

from pydantic_settings import BaseSettings
from pathlib import Path


def _read_secret(path: str) -> str:
    """Read a Docker secret from a file path."""
    p = Path(path)
    if p.exists():
        return p.read_text().strip()
    return ""


class Settings(BaseSettings):
    # Ollama
    ollama_base_url: str = "http://192.168.80.200:11434"
    embed_model: str = "nomic-embed-text"
    llm_model: str = "qwen2.5:7b"
    embed_dims: int = 768

    # Qdrant
    qdrant_url: str = "http://qdrant:6333"
    qdrant_api_key_file: str = "/run/secrets/qdrant_api_key"
    qdrant_collection_prefix: str = "lab_"

    # Postgres
    pg_host: str = "192.168.80.200"
    pg_port: int = 5432
    pg_db: str = "rag"
    pg_user: str = "rag"
    pg_password_file: str = "/run/secrets/pg_rag_pass"

    # MinIO
    minio_endpoint: str = "minio:9000"
    minio_access_key_file: str = "/run/secrets/minio_access_key"
    minio_secret_key_file: str = "/run/secrets/minio_secret_key"
    minio_bucket: str = "rag-documents"
    minio_secure: bool = False

    # RAG parameters
    chunk_size: int = 1000
    chunk_overlap: int = 150
    top_k: int = 5

    # API
    api_title: str = "Lab RAG API"
    api_version: str = "1.0.0"
    log_level: str = "INFO"

    @property
    def qdrant_api_key(self) -> str:
        return _read_secret(self.qdrant_api_key_file)

    @property
    def pg_password(self) -> str:
        return _read_secret(self.pg_password_file)

    @property
    def pg_dsn(self) -> str:
        return (
            f"postgresql+psycopg2://{self.pg_user}:{self.pg_password}"
            f"@{self.pg_host}:{self.pg_port}/{self.pg_db}"
        )

    @property
    def minio_access_key(self) -> str:
        return _read_secret(self.minio_access_key_file)

    @property
    def minio_secret_key(self) -> str:
        return _read_secret(self.minio_secret_key_file)

    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"


settings = Settings()
