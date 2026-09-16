"""Unit tests for db.get_connection()'s env-var fallback and DSN
validation. No Docker/Postgres needed -- psycopg.connect() itself is
monkeypatched out; these tests are entirely about what DSN value
get_connection() computes and validates, not about actually connecting
(that's covered by the Docker-based integration tests elsewhere).

Written after a real CI failure: a GitHub Actions run hit
`psycopg.ProgrammingError: invalid connection option "SUPABASE_DB_URL"`
-- not a code bug (confirmed: os.environ["SUPABASE_DB_URL"] is a
correct value lookup by key, verified by reading the traceback's exact
line numbers against this file), but the failure mode itself (a bad
value reaching psycopg with no clear diagnosis) was worth guarding
against directly, hence the new validation in get_connection() and the
tests below.
"""

import pytest

from nimtracker import db


def test_get_connection_uses_env_var_value_not_its_name(monkeypatch):
    # Directly proves the actual bug report's premise is false for this
    # code path: with SUPABASE_DB_URL set and no --db-url/dsn argument
    # passed (exactly how main() calls this in both scripts), the value
    # handed to psycopg is the env var's VALUE, never its NAME.
    real_value = "postgresql://user:pass@example.com:5432/postgres"
    monkeypatch.setenv("SUPABASE_DB_URL", real_value)

    captured = {}

    def fake_connect(dsn, **kwargs):
        captured["dsn"] = dsn
        return "fake-connection"

    monkeypatch.setattr(db.psycopg, "connect", fake_connect)

    db.get_connection()

    assert captured["dsn"] == real_value
    assert captured["dsn"] != "SUPABASE_DB_URL"


def test_get_connection_rejects_a_dsn_that_is_not_a_connection_string(monkeypatch):
    # Reproduces the actual real-world failure: the env var's value was
    # (apparently) literally the string "SUPABASE_DB_URL" -- a GitHub
    # secret whose VALUE field got set to its own NAME by mistake. This
    # must fail with our own clear error before ever reaching psycopg,
    # not propagate to a cryptic "invalid connection option" traceback.
    monkeypatch.setenv("SUPABASE_DB_URL", "SUPABASE_DB_URL")

    with pytest.raises(ValueError, match="does not look like a Postgres connection string"):
        db.get_connection()


def test_get_connection_error_never_echoes_the_bad_value(monkeypatch):
    # The error message is diagnostic-only -- it must never include any
    # part of the actual (possibly sensitive) value, since this can end
    # up in a CI log.
    secret_looking_value = "not-a-real-dsn-but-pretend-this-has-a-password-in-it"
    monkeypatch.setenv("SUPABASE_DB_URL", secret_looking_value)

    with pytest.raises(ValueError) as exc_info:
        db.get_connection()

    assert secret_looking_value not in str(exc_info.value)


def test_get_connection_explicit_dsn_overrides_env_var(monkeypatch):
    monkeypatch.setenv("SUPABASE_DB_URL", "postgresql://from-env/postgres")

    captured = {}

    def fake_connect(dsn, **kwargs):
        captured["dsn"] = dsn
        return "fake-connection"

    monkeypatch.setattr(db.psycopg, "connect", fake_connect)

    db.get_connection("postgresql://explicit/postgres")

    assert captured["dsn"] == "postgresql://explicit/postgres"
