"""Integration tests for run_catalog_job() / db.py, against a real
throwaway local Postgres container -- same discipline as the db/tests/
*.sql scenario tests, just exercised through the actual Python code
path instead of raw SQL.

Scrape results are synthetic (monkeypatched), not real Playwright/
network calls -- this is deliberate: it lets the fallback/retry
branches be tested precisely (list-scrape failure, one model's detail
failure, a redirecting model's detail failure) instead of hoping to
observe them live. The real scraping itself was already proven against
the live site in Phase 0 / the Phase 2 planning pass.

Requires Docker. Fixtures (pg_dsn, conn, seed_model) live in
conftest.py, shared with test_completions_probe.py. Spins up and tears
down its own container -- `pytest backend/tests/test_catalog_job.py`
is self-contained, no manual setup needed. NEVER points at the real
Supabase project -- see CLAUDE.md, Hard rules.
"""

import time

from nimtracker import catalog_scraper


def _fake_list_row(catalog_href: str, **overrides) -> dict:
    row = {
        "provider": "Acme",
        "model_name": "widget-9000",
        "catalog_href": catalog_href,
        "description": "a widget",
        "badges": ["Free Endpoint"],
        "tags": ["chat"],
        "deprecation_days": None,
        "is_free_endpoint": True,
    }
    row.update(overrides)
    return row


def _fake_detail(resolved_slug: str, **overrides) -> dict:
    row = {
        "has_specifications_sidebar": True,
        "output_modalities": "Text",
        "is_text_completion_model": True,
        "context_length": "128K",
        "parameters": "9B",
        "function_calling": True,
        "structured_output": False,
        "reasoning": False,
        "code_snippet_found": True,
        "api_model_id_scraped": resolved_slug.lstrip("/"),
        "api_model_id_derived": resolved_slug.lstrip("/"),
        "api_model_id_mismatch": False,
        "resolved_slug": resolved_slug,
        "slug_redirected": False,
    }
    row.update(overrides)
    return row


def test_upsert_model_sets_first_discovered_at_only_on_insert(conn, seed_model):
    seed_model(conn, slug="acme/a", catalog_href="/acme/a")
    with conn.cursor() as cur:
        cur.execute("select first_discovered_at, updated_at from model where slug = 'acme/a'")
        first_row = cur.fetchone()

    time.sleep(1.1)  # ensure now() genuinely advances between upserts
    seed_model(conn, slug="acme/a", catalog_href="/acme/a", model_name="widget-9001")
    with conn.cursor() as cur:
        cur.execute("select first_discovered_at, updated_at, model_name from model where slug = 'acme/a'")
        second_row = cur.fetchone()

    assert second_row["first_discovered_at"] == first_row["first_discovered_at"]
    assert second_row["updated_at"] > first_row["updated_at"]
    assert second_row["model_name"] == "widget-9001"


def test_upsert_model_does_not_touch_lifecycle_fields(conn, seed_model):
    seed_model(conn, slug="acme/b", catalog_href="/acme/b")
    with conn.cursor() as cur:
        cur.execute(
            "update model set last_seen_working_at = now(), delisted_at = now(), delisted_reason = 'test' "
            "where slug = 'acme/b'"
        )
    conn.commit()

    seed_model(conn, slug="acme/b", catalog_href="/acme/b", model_name="widget-9002")

    with conn.cursor() as cur:
        cur.execute("select last_seen_working_at, delisted_at, delisted_reason from model where slug = 'acme/b'")
        row = cur.fetchone()

    assert row["last_seen_working_at"] is not None
    assert row["delisted_at"] is not None
    assert row["delisted_reason"] == "test"


def test_run_catalog_job_list_scrape_failure_uses_db_fallback(conn, seed_model, monkeypatch):
    seed_model(conn, slug="acme/a", catalog_href="/acme/a")
    seed_model(conn, slug="acme/b", catalog_href="/acme/b")

    monkeypatch.setattr(catalog_scraper, "scrape_list_with_retry", lambda browser, url, retries=1: None)

    summary = catalog_scraper.run_catalog_job(browser=None, conn=conn, delay=0)

    assert summary["list_source"] == "db_fallback"
    assert summary["models_found_count"] == 2

    with conn.cursor() as cur:
        cur.execute("select list_source, models_found_count from catalog_run")
        run_row = cur.fetchone()
        assert run_row["list_source"] == "db_fallback"
        assert run_row["models_found_count"] == 2

        cur.execute("select count(*) as n from model")
        assert cur.fetchone()["n"] == 2  # untouched, no new rows


def test_run_catalog_job_detail_scrape_failure_falls_back_to_existing_row(conn, seed_model, monkeypatch):
    seed_model(
        conn,
        slug="acme/widget-9000",
        catalog_href="/acme/widget-9000",
        model_name="widget-9000 (old name)",
        parameters="9B",
    )

    fresh_list_row = _fake_list_row("/acme/widget-9000", model_name="widget-9000 (new name)")
    monkeypatch.setattr(
        catalog_scraper, "scrape_list_with_retry",
        lambda browser, url, retries=1: [fresh_list_row],
    )
    monkeypatch.setattr(
        catalog_scraper, "scrape_detail_with_retry",
        lambda browser, catalog_href, debug=False, retries=1: None,
    )

    summary = catalog_scraper.run_catalog_job(browser=None, conn=conn, delay=0)
    assert summary["detail_db_fallback"] == 1

    with conn.cursor() as cur:
        cur.execute("select * from model where slug = 'acme/widget-9000'")
        row = cur.fetchone()

    assert row["detail_source"] == "db_fallback"
    assert row["parameters"] == "9B"  # detail-page field -- fell back to DB
    assert row["model_name"] == "widget-9000 (new name)"  # list-page field -- refreshed from today's scrape


def test_run_catalog_job_redirecting_href_finds_existing_row_via_catalog_href(conn, seed_model, monkeypatch):
    # Simulates a PRIOR successful run that resolved a redirecting href
    # -- the real, confirmed ising-calibration case.
    seed_model(
        conn,
        slug="nvidia/ising-calibration-1.5-31b",
        catalog_href="/nvidia/ising-calibration-1-35b-a3b",
    )

    fresh_list_row = _fake_list_row("/nvidia/ising-calibration-1-35b-a3b", provider="NVIDIA")
    monkeypatch.setattr(
        catalog_scraper, "scrape_list_with_retry",
        lambda browser, url, retries=1: [fresh_list_row],
    )
    monkeypatch.setattr(
        catalog_scraper, "scrape_detail_with_retry",
        lambda browser, catalog_href, debug=False, retries=1: None,
    )

    catalog_scraper.run_catalog_job(browser=None, conn=conn, delay=0)

    with conn.cursor() as cur:
        cur.execute("select count(*) as n from model")
        assert cur.fetchone()["n"] == 1  # no duplicate row created

        cur.execute("select slug, detail_source from model")
        row = cur.fetchone()
        assert row["slug"] == "nvidia/ising-calibration-1.5-31b"  # unchanged, not overwritten with the raw href
        assert row["detail_source"] == "db_fallback"


def test_run_catalog_job_brand_new_model_with_failed_detail_scrape_still_inserted(conn, monkeypatch):
    fresh_list_row = _fake_list_row("/newco/new-model", provider="Newco", model_name="new-model")
    monkeypatch.setattr(
        catalog_scraper, "scrape_list_with_retry",
        lambda browser, url, retries=1: [fresh_list_row],
    )
    monkeypatch.setattr(
        catalog_scraper, "scrape_detail_with_retry",
        lambda browser, catalog_href, debug=False, retries=1: None,
    )

    summary = catalog_scraper.run_catalog_job(browser=None, conn=conn, delay=0)
    assert summary["detail_unknown"] == 1

    with conn.cursor() as cur:
        cur.execute("select * from model where slug = 'newco/new-model'")
        row = cur.fetchone()

    assert row is not None
    assert row["detail_source"] == "unknown"
    assert row["api_model_id"] == "newco/new-model"
    assert row["api_model_id_source"] == "derived_fallback"
    assert row["has_specifications_sidebar"] is None


def test_run_catalog_job_live_success_upserts_with_resolved_slug(conn, monkeypatch):
    # The href redirects (differs from resolved_slug) -- proves a LIVE
    # success also uses the resolved slug, not the raw href, as the key.
    fresh_list_row = _fake_list_row("/acme/old-name")
    fake_detail = _fake_detail("/acme/new-name", slug_redirected=True)
    monkeypatch.setattr(
        catalog_scraper, "scrape_list_with_retry",
        lambda browser, url, retries=1: [fresh_list_row],
    )
    monkeypatch.setattr(
        catalog_scraper, "scrape_detail_with_retry",
        lambda browser, catalog_href, debug=False, retries=1: fake_detail,
    )

    summary = catalog_scraper.run_catalog_job(browser=None, conn=conn, delay=0)
    assert summary["detail_live"] == 1

    with conn.cursor() as cur:
        cur.execute("select * from model")
        rows = cur.fetchall()

    assert len(rows) == 1
    row = rows[0]
    assert row["slug"] == "acme/new-name"  # resolved, not the raw "acme/old-name" href
    assert row["catalog_href"] == "/acme/old-name"  # raw href preserved separately
    assert row["detail_source"] == "live"
    assert row["api_model_id_source"] == "scraped_snippet"
