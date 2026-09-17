"""Integration tests for run_completions_sweep() / db.py, against a real
throwaway local Postgres container. HTTP calls are monkeypatched (no
real network calls, no real NIM_API_KEY needed) -- this lets every
resolution/error-taxonomy branch and the execution summary computation
be tested precisely, rather than depending on live API behavior.

Requires Docker. Fixtures (pg_dsn, conn, seed_model) live in
conftest.py, shared with test_catalog_job.py. NEVER points at the real
Supabase project -- see CLAUDE.md, Hard rules.
"""

from nimtracker import completions_probe


def _fake_result(**overrides):
    row = {
        "success": True,
        "error_category": None,
        "error_body": None,
        "response_time_s": 1.0,
        "completion_tokens": 42,
        "prompt_tokens": 10,
        "tokens_per_sec": 42.0,
        "response_text": "hello",
    }
    row.update(overrides)
    return row


def test_run_completions_sweep_mixed_results(conn, seed_model, monkeypatch):
    seed_model(conn, slug="acme/a", catalog_href="/acme/a", api_model_id="acme/a")
    seed_model(conn, slug="acme/b", catalog_href="/acme/b", api_model_id="acme/b")
    seed_model(conn, slug="acme/c", catalog_href="/acme/c", api_model_id="acme/c")

    results_by_id = {
        "acme/a": _fake_result(response_time_s=2.5),
        "acme/b": _fake_result(
            success=False, error_category="timeout", response_time_s=240.0,
            completion_tokens=None, prompt_tokens=None, tokens_per_sec=None, response_text=None,
        ),
        "acme/c": _fake_result(response_time_s=1.2),  # fastest of the two successes
    }

    monkeypatch.setattr(
        completions_probe, "call_model",
        lambda client, api_key, api_model_id: results_by_id[api_model_id],
    )

    summary = completions_probe.run_completions_sweep(conn, api_key="fake-key")

    assert summary["models_tested_count"] == 3
    assert summary["models_succeeded_count"] == 2
    assert summary["fastest_model_slug"] == "acme/c"
    assert summary["fastest_response_time_s"] == 1.2

    with conn.cursor() as cur:
        cur.execute("select count(*) as n from execution")
        assert cur.fetchone()["n"] == 1

        cur.execute("select count(*) as n from result")
        assert cur.fetchone()["n"] == 3

        cur.execute("select model_slug, success, error_category, resolution from result order by model_slug")
        rows = {r["model_slug"]: r for r in cur.fetchall()}

    assert rows["acme/a"]["resolution"] == "counted_working"
    assert rows["acme/b"]["success"] is False
    assert rows["acme/b"]["error_category"] == "timeout"
    assert rows["acme/b"]["resolution"] == "counted_error"
    assert rows["acme/c"]["resolution"] == "counted_working"


def test_run_completions_sweep_all_failures_no_fastest(conn, seed_model, monkeypatch):
    seed_model(conn, slug="acme/a", catalog_href="/acme/a", api_model_id="acme/a")

    monkeypatch.setattr(
        completions_probe, "call_model",
        lambda client, api_key, api_model_id: _fake_result(
            success=False, error_category="server_error",
            completion_tokens=None, prompt_tokens=None, tokens_per_sec=None, response_text=None,
        ),
    )

    summary = completions_probe.run_completions_sweep(conn, api_key="fake-key")

    assert summary["models_succeeded_count"] == 0
    assert summary["fastest_model_slug"] is None
    assert summary["fastest_response_time_s"] is None


def test_run_completions_sweep_tests_no_sidebar_model_never_excludes(conn, seed_model, monkeypatch):
    # Documents the intentional v1 limitation: even a model with no
    # heuristic signal at all (the 'unknown' detail_source case) gets
    # tested and, on failure, counts as a real error -- never silently
    # excluded. See CLAUDE.md, "Core domain logic."
    seed_model(
        conn, slug="acme/no-sidebar", catalog_href="/acme/no-sidebar", api_model_id="acme/no-sidebar",
        has_specifications_sidebar=None, is_text_completion_model=None,
        output_modalities=None, detail_source="unknown",
    )

    monkeypatch.setattr(
        completions_probe, "call_model",
        lambda client, api_key, api_model_id: _fake_result(
            success=False, error_category="other",
            completion_tokens=None, prompt_tokens=None, tokens_per_sec=None, response_text=None,
        ),
    )

    summary = completions_probe.run_completions_sweep(conn, api_key="fake-key")

    assert summary["models_tested_count"] == 1  # counted, not excluded
    with conn.cursor() as cur:
        cur.execute("select resolution from result where model_slug = 'acme/no-sidebar'")
        assert cur.fetchone()["resolution"] == "counted_error"


def test_run_completions_sweep_calls_each_model_exactly_once(conn, seed_model, monkeypatch):
    seed_model(conn, slug="acme/a", catalog_href="/acme/a", api_model_id="acme/a")
    seed_model(conn, slug="acme/b", catalog_href="/acme/b", api_model_id="acme/b")

    call_count = {"n": 0}

    def fake_call_model(client, api_key, api_model_id):
        call_count["n"] += 1
        return _fake_result()

    monkeypatch.setattr(completions_probe, "call_model", fake_call_model)
    completions_probe.run_completions_sweep(conn, api_key="fake-key")

    assert call_count["n"] == 2  # exactly one attempt per model -- no in-run retries


def test_run_completions_sweep_success_sets_last_seen_working_at(conn, seed_model, monkeypatch):
    # The gap found while building Phase 5's Models table: this column
    # existed since Phase 1 but no code ever wrote it before
    # db.update_model_lifecycle. A fresh success must move it forward
    # and must NOT touch delisted_at/delisted_reason.
    seed_model(conn, slug="acme/a", catalog_href="/acme/a", api_model_id="acme/a")

    monkeypatch.setattr(
        completions_probe, "call_model",
        lambda client, api_key, api_model_id: _fake_result(),
    )
    completions_probe.run_completions_sweep(conn, api_key="fake-key")

    with conn.cursor() as cur:
        cur.execute("select last_seen_working_at, delisted_at, delisted_reason from model where slug = 'acme/a'")
        row = cur.fetchone()
    assert row["last_seen_working_at"] is not None
    assert row["delisted_at"] is None
    assert row["delisted_reason"] is None


def test_run_completions_sweep_removed_failure_sets_delisted_fields(conn, seed_model, monkeypatch):
    seed_model(conn, slug="acme/a", catalog_href="/acme/a", api_model_id="acme/a")

    monkeypatch.setattr(
        completions_probe, "call_model",
        lambda client, api_key, api_model_id: _fake_result(
            success=False, error_category="removed", error_body="Model retired 2026-01-01.",
            completion_tokens=None, prompt_tokens=None, tokens_per_sec=None, response_text=None,
        ),
    )
    completions_probe.run_completions_sweep(conn, api_key="fake-key")

    with conn.cursor() as cur:
        cur.execute("select last_seen_working_at, delisted_at, delisted_reason from model where slug = 'acme/a'")
        row = cur.fetchone()
    assert row["last_seen_working_at"] is None  # never had a success -- must stay null
    assert row["delisted_at"] is not None
    assert row["delisted_reason"] == "Model retired 2026-01-01."


def test_run_completions_sweep_non_removed_failure_leaves_lifecycle_fields_untouched(conn, seed_model, monkeypatch):
    # A single timeout/rate-limit/etc. is not a delisting signal --
    # that's what model_state_as_of()'s live 24h-rolling-window check is
    # for. Only an explicit 'removed' classification (404/410) sets
    # delisted_at directly.
    seed_model(conn, slug="acme/a", catalog_href="/acme/a", api_model_id="acme/a")

    monkeypatch.setattr(
        completions_probe, "call_model",
        lambda client, api_key, api_model_id: _fake_result(
            success=False, error_category="timeout",
            completion_tokens=None, prompt_tokens=None, tokens_per_sec=None, response_text=None,
        ),
    )
    completions_probe.run_completions_sweep(conn, api_key="fake-key")

    with conn.cursor() as cur:
        cur.execute("select last_seen_working_at, delisted_at, delisted_reason from model where slug = 'acme/a'")
        row = cur.fetchone()
    assert row["last_seen_working_at"] is None
    assert row["delisted_at"] is None
    assert row["delisted_reason"] is None


def test_run_completions_sweep_recovery_clears_delisted_fields(conn, seed_model, monkeypatch):
    # The real documented case (CLAUDE.md): nemotron-3-nano-30b-a3b
    # worked, then 410'd, then worked again in a later run. A fresh
    # success must clear a prior delisting, not leave it stuck.
    seed_model(conn, slug="acme/a", catalog_href="/acme/a", api_model_id="acme/a")

    monkeypatch.setattr(
        completions_probe, "call_model",
        lambda client, api_key, api_model_id: _fake_result(
            success=False, error_category="removed", error_body="410",
            completion_tokens=None, prompt_tokens=None, tokens_per_sec=None, response_text=None,
        ),
    )
    completions_probe.run_completions_sweep(conn, api_key="fake-key")

    with conn.cursor() as cur:
        cur.execute("select delisted_at from model where slug = 'acme/a'")
        assert cur.fetchone()["delisted_at"] is not None

    monkeypatch.setattr(
        completions_probe, "call_model",
        lambda client, api_key, api_model_id: _fake_result(),
    )
    completions_probe.run_completions_sweep(conn, api_key="fake-key")

    with conn.cursor() as cur:
        cur.execute("select last_seen_working_at, delisted_at, delisted_reason from model where slug = 'acme/a'")
        row = cur.fetchone()
    assert row["last_seen_working_at"] is not None
    assert row["delisted_at"] is None
    assert row["delisted_reason"] is None


def test_run_completions_sweep_uses_api_model_id_not_slug(conn, seed_model, monkeypatch):
    # slug and api_model_id deliberately differ here to prove the call
    # uses api_model_id -- this is the entire reason that column exists.
    seed_model(
        conn, slug="acme/resolved-slug", catalog_href="/acme/resolved-slug",
        api_model_id="acme/literal-api-id",
    )

    seen_ids = []

    def fake_call_model(client, api_key, api_model_id):
        seen_ids.append(api_model_id)
        return _fake_result()

    monkeypatch.setattr(completions_probe, "call_model", fake_call_model)
    completions_probe.run_completions_sweep(conn, api_key="fake-key")

    assert seen_ids == ["acme/literal-api-id"]
