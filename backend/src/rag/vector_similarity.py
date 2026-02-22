import json
import os
import re
from contextlib import contextmanager
import snowflake.connector
from dotenv import load_dotenv

load_dotenv()

def _get_connection_params() -> dict[str, str]:
    """Load Snowflake connection params from environment."""
    params: dict[str, str] = {}
    for key, val in [
        ("user", os.getenv("SNOWFLAKE_USER")),
        ("password", os.getenv("SNOWFLAKE_PASSWORD")),
        ("account", os.getenv("SNOWFLAKE_ACCOUNT")),
        ("warehouse", os.getenv("SNOWFLAKE_WAREHOUSE")),
        ("database", os.getenv("SNOWFLAKE_DATABASE")),
        ("schema", os.getenv("SNOWFLAKE_SCHEMA")),
        ("role", os.getenv("SNOWFLAKE_ROLE")),
    ]:
        if val:
            params[key] = val
    return params


@contextmanager
def get_connection():
    """Context manager for Snowflake connection."""
    params = _get_connection_params()
    if not all([params.get("user"), params.get("password"), params.get("account")]):
        raise ValueError(
            "Missing required env: SNOWFLAKE_USER, SNOWFLAKE_PASSWORD, SNOWFLAKE_ACCOUNT"
        )
    conn = snowflake.connector.connect(**params)
    try:
        yield conn
    finally:
        conn.close()

def vector_similarity(a: str, b: str) -> float:
    """Compute cosine similarity between two texts using Snowflake Cortex embeddings."""
    with get_connection() as conn:
        cur = conn.cursor()
        cur.execute(
            """
            SELECT VECTOR_COSINE_SIMILARITY(
                SNOWFLAKE.CORTEX.EMBED_TEXT_768('snowflake-arctic-embed-m', %(a)s),
                SNOWFLAKE.CORTEX.EMBED_TEXT_768('snowflake-arctic-embed-m', %(b)s)
            ) AS similarity
            FROM hacklytics.public.meeting
            """,
            {"a": a, "b": b},
        )
        row = cur.fetchone()
        return float(row[0]) if row and row[0] is not None else 0.0

def three_most_similar(text: str, top_n: int = 3) -> list[tuple[str, float]]:
    """Find the three most similar texts to the given text using Snowflake Cortex embeddings."""
    with get_connection() as conn:
        cur = conn.cursor()
        cur.execute(
            """
            SELECT text, similarity FROM (
                SELECT text, VECTOR_COSINE_SIMILARITY(
                    SNOWFLAKE.CORTEX.EMBED_TEXT_768('snowflake-arctic-embed-m', %(text)s),
                    SNOWFLAKE.CORTEX.EMBED_TEXT_768('snowflake-arctic-embed-m', text)
                ) AS similarity FROM hacklytics.public.meeting
            ) ORDER BY similarity DESC LIMIT %(top_n)s
            """,
            {"text": text, "top_n": top_n},
        )
        rows = cur.fetchall()
        return [(row[0], row[1]) for row in rows]