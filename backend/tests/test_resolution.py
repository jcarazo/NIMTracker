"""Unit tests for resolution.py -- pure functions, no I/O, no Docker,
no database. Run with: pytest backend/tests/test_resolution.py
"""

import pytest

from nimtracker.resolution import classify_error, resolve


@pytest.mark.parametrize(
    "status_code,body_text,expected",
    [
        (404, "", "removed"),
        (410, "", "removed"),
        (410, "end of life notice", "removed"),
        (429, "", "rate_limited"),
        (429, "rate limit exceeded", "rate_limited"),
        (400, "model is DEGRADED right now", "degraded"),
        (400, "some other bad request, not the marker", "other"),
        (500, "", "server_error"),
        (502, "", "server_error"),
        (503, "", "server_error"),
        (401, "", "other"),  # narrowed from the reference script's "access_denied"
        (403, "", "other"),
        (None, "", "other"),  # narrowed from the reference script's "network_error"
        (200, "", "other"),  # classify_error is never called with a success code in practice, but must not crash
    ],
)
def test_classify_error(status_code, body_text, expected):
    assert classify_error(status_code, body_text) == expected


def test_classify_error_only_returns_valid_categories():
    from nimtracker.resolution import ERROR_CATEGORIES

    cases = [404, 410, 429, 400, 500, 401, 403, None, 200, 999]
    for status_code in cases:
        assert classify_error(status_code, "") in ERROR_CATEGORIES


def test_resolve_success_always_counted_working():
    assert resolve(True) == "counted_working"


def test_resolve_failure_always_counted_error():
    assert resolve(False) == "counted_error"


def test_resolve_never_excludes():
    # Documents the intentional v1 limitation (see CLAUDE.md): there is
    # currently no code path that produces "excluded_non_text" at all.
    from nimtracker.resolution import RESOLUTIONS

    assert "excluded_non_text" in RESOLUTIONS  # still a valid schema value
    assert resolve(True) != "excluded_non_text"
    assert resolve(False) != "excluded_non_text"
