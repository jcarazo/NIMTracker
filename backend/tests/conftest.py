"""Shared pytest fixtures for the integration test suites (test_catalog_job.py,
test_completions_probe.py). Spins up and tears down its own throwaway
Postgres container -- fully self-contained, no manual setup needed.
Requires Docker. NEVER points at the real Supabase project -- see
CLAUDE.md, Hard rules.
"""

import subprocess
import time
from pathlib import Path

import psycopg
import pytest

from nimtracker import db

REPO_ROOT = Path(__file__).resolve().parents[2]
CONTAINER_NAME = "nimtracker-pytest-pg"
PG_PORT = 55499
DSN = f"postgresql://postgres:test@localhost:{PG_PORT}/postgres"


@pytest.fixture(scope="session")
def pg_dsn():
    subprocess.run(["docker", "rm", "-f", CONTAINER_NAME], capture_output=True)
    subprocess.run(
        [
            "docker", "run", "-d", "--name", CONTAINER_NAME,
            "-e", "POSTGRES_PASSWORD=test",
            "-p", f"{PG_PORT}:5432",
            "postgres:16",
        ],
        check=True,
        capture_output=True,
    )

    for _ in range(30):
        result = subprocess.run(
            ["docker", "exec", CONTAINER_NAME, "pg_isready", "-U", "postgres"],
            capture_output=True,
        )
        if result.returncode == 0:
            break
        time.sleep(1)
    else:
        subprocess.run(["docker", "rm", "-f", CONTAINER_NAME], capture_output=True)
        raise RuntimeError("Postgres container did not become ready in time")

    schema_sql = (REPO_ROOT / "db" / "schema.sql").read_text()
    with psycopg.connect(DSN, autocommit=True) as conn:
        conn.execute(schema_sql)

    yield DSN

    subprocess.run(["docker", "rm", "-f", CONTAINER_NAME], capture_output=True)


@pytest.fixture
def conn(pg_dsn):
    """Fresh, truncated state for every test -- some tests exercise
    run_catalog_job()/run_completions_sweep(), which commit internally
    (each is meant to be one atomic unit of work), so a rollback-based
    isolation pattern doesn't work here; truncate-before is simpler and
    uniform for every test.
    """
    c = db.get_connection(pg_dsn)
    with c.cursor() as cur:
        cur.execute("truncate table result, execution, catalog_run, model cascade")
    c.commit()
    yield c
    c.close()


@pytest.fixture
def seed_model():
    """Factory fixture: seed_model(conn, **overrides) inserts one model
    row with sensible defaults, returns the row dict actually inserted.
    """

    def _seed(conn, **overrides):
        row = {
            "slug": "acme/widget-9000",
            "provider": "Acme",
            "model_name": "widget-9000",
            "description": "a widget",
            "tags": ["chat"],
            "is_free_endpoint": True,
            "deprecation_days": None,
            "catalog_href": "/acme/widget-9000",
            "output_modalities": "Text",
            "has_specifications_sidebar": True,
            "is_text_completion_model": True,
            "context_length": "128K",
            "parameters": "9B",
            "function_calling": True,
            "structured_output": False,
            "reasoning": False,
            "detail_source": "live",
            "api_model_id": "acme/widget-9000",
            "api_model_id_source": "scraped_snippet",
        }
        row.update(overrides)
        db.upsert_model(conn, row)
        conn.commit()
        return row

    return _seed
