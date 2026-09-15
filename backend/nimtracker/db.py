"""psycopg3 connection + typed read/write helpers for the catalog job
(Phase 2, catalog_scraper.py) and the completions job (Phase 3,
completions_probe.py).

Deliberately no business logic here -- fallback/retry/resolution
decisions live in the callers. This module is only responsible for
shaping SQL around the schema in db/schema.sql.
"""

import os

import psycopg
from psycopg.rows import dict_row


def get_connection(dsn: str | None = None) -> psycopg.Connection:
    """dsn defaults to the SUPABASE_DB_URL env var if not passed
    explicitly. Passing it explicitly (e.g. in tests, pointed at a local
    throwaway container) avoids any risk of a leftover env var silently
    redirecting a test run at the real project.
    """
    dsn = dsn or os.environ["SUPABASE_DB_URL"]
    return psycopg.connect(dsn, row_factory=dict_row)


def get_model_by_slug(conn: psycopg.Connection, slug: str) -> dict | None:
    with conn.cursor() as cur:
        cur.execute("select * from model where slug = %s", (slug,))
        return cur.fetchone()


def get_model_by_catalog_href(conn: psycopg.Connection, catalog_href: str) -> dict | None:
    """Secondary fallback lookup for a model whose catalog-list href
    redirects to a different resolved slug -- see the catalog_href
    column comment in db/schema.sql. Only useful when a live navigation
    (which would give the resolved slug directly) isn't available.
    """
    with conn.cursor() as cur:
        cur.execute("select * from model where catalog_href = %s", (catalog_href,))
        return cur.fetchone()


def count_models(conn: psycopg.Connection) -> int:
    with conn.cursor() as cur:
        cur.execute("select count(*) as n from model")
        return cur.fetchone()["n"]


_UPSERT_MODEL_SQL = """
insert into model (
  slug, provider, model_name, description, tags,
  is_free_endpoint, deprecation_days, catalog_href,
  output_modalities, has_specifications_sidebar, is_text_completion_model,
  context_length, parameters, function_calling, structured_output, reasoning,
  detail_source, api_model_id, api_model_id_source
) values (
  %(slug)s, %(provider)s, %(model_name)s, %(description)s, %(tags)s,
  %(is_free_endpoint)s, %(deprecation_days)s, %(catalog_href)s,
  %(output_modalities)s, %(has_specifications_sidebar)s, %(is_text_completion_model)s,
  %(context_length)s, %(parameters)s, %(function_calling)s, %(structured_output)s, %(reasoning)s,
  %(detail_source)s, %(api_model_id)s, %(api_model_id_source)s
)
on conflict (slug) do update set
  provider = excluded.provider,
  model_name = excluded.model_name,
  description = excluded.description,
  tags = excluded.tags,
  is_free_endpoint = excluded.is_free_endpoint,
  deprecation_days = excluded.deprecation_days,
  catalog_href = excluded.catalog_href,
  output_modalities = excluded.output_modalities,
  has_specifications_sidebar = excluded.has_specifications_sidebar,
  is_text_completion_model = excluded.is_text_completion_model,
  context_length = excluded.context_length,
  parameters = excluded.parameters,
  function_calling = excluded.function_calling,
  structured_output = excluded.structured_output,
  reasoning = excluded.reasoning,
  detail_source = excluded.detail_source,
  api_model_id = excluded.api_model_id,
  api_model_id_source = excluded.api_model_id_source,
  updated_at = now()
"""
# Deliberately NOT touched, even on conflict:
#   first_discovered_at -- keeps its insert-time default; must never
#     reset on a later refresh.
#   last_seen_working_at, delisted_at, delisted_reason -- lifecycle
#     fields owned by the completions job (Phase 3), driven by result
#     history and explicit 410s, not by catalog discovery.


def upsert_model(conn: psycopg.Connection, model: dict) -> None:
    with conn.cursor() as cur:
        cur.execute(_UPSERT_MODEL_SQL, model)


def insert_catalog_run(conn: psycopg.Connection, list_source: str, models_found_count: int) -> None:
    with conn.cursor() as cur:
        cur.execute(
            "insert into catalog_run (list_source, models_found_count) values (%s, %s)",
            (list_source, models_found_count),
        )


def get_all_models(conn: psycopg.Connection) -> list[dict]:
    """Every model, unconditionally -- the completions sweep tests every
    catalog-listed model every run, no filtering on heuristic fields
    (see CLAUDE.md, "no heuristic may ever prevent a model from being
    tested").
    """
    with conn.cursor() as cur:
        cur.execute("select slug, provider, model_name, api_model_id from model order by slug")
        return cur.fetchall()


def insert_execution(conn: psycopg.Connection, execution: dict) -> str:
    with conn.cursor() as cur:
        cur.execute(
            """
            insert into execution (
              started_at, models_tested_count, models_succeeded_count,
              fastest_model_slug, fastest_response_time_s
            ) values (
              %(started_at)s, %(models_tested_count)s, %(models_succeeded_count)s,
              %(fastest_model_slug)s, %(fastest_response_time_s)s
            )
            returning id
            """,
            execution,
        )
        return cur.fetchone()["id"]


def insert_result(conn: psycopg.Connection, result: dict) -> None:
    with conn.cursor() as cur:
        cur.execute(
            """
            insert into result (
              execution_id, model_slug, success, error_category, error_body,
              response_time_s, completion_tokens, prompt_tokens, tokens_per_sec,
              response_text, resolution
            ) values (
              %(execution_id)s, %(model_slug)s, %(success)s, %(error_category)s, %(error_body)s,
              %(response_time_s)s, %(completion_tokens)s, %(prompt_tokens)s, %(tokens_per_sec)s,
              %(response_text)s, %(resolution)s
            )
            """,
            result,
        )
