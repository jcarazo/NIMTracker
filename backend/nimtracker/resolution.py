"""Pure, isolated business logic for the completions sweep (Phase 3):
error taxonomy classification and the success -> resolution mapping.
No I/O, no network, no DB -- deliberately isolated so this, "the single
most important piece of business logic in the app" per the
implementation plan, can be unit tested directly.
"""

ERROR_CATEGORIES = {
    "removed", "rate_limited", "degraded", "timeout",
    "server_error", "empty_response", "other",
}

RESOLUTIONS = {"counted_working", "counted_error", "excluded_non_text"}


def classify_error(status_code: int | None, body_text: str) -> str:
    """Classifies a failed completions call's HTTP status/body into the
    fixed error taxonomy (db/schema.sql's `result.error_category` CHECK
    constraint). Only for calls that got an HTTP response back -- never
    called for a timeout or connection-level failure, which
    completions_probe.py classifies directly from the exception type
    (there's no status code to inspect in that case).

    Ported from the reference check_completions.py, narrowed: that
    script empirically found two more categories that don't exist in
    our schema -- 401/403 ("access_denied") and connection-level
    failures ("network_error") -- both fold into "other" here. A
    deliberate narrowing to match our fixed 7-category schema, not an
    oversight.
    """
    if status_code in (404, 410):
        return "removed"
    if status_code == 429:
        return "rate_limited"
    if status_code == 400 and "DEGRADED" in body_text:
        return "degraded"
    if status_code is not None and status_code >= 500:
        return "server_error"
    return "other"


def resolve(success: bool) -> str:
    """success -> counted_working / counted_error.

    `excluded_non_text` is a valid `result.resolution` value in the
    schema but is intentionally UNREACHABLE in v1 -- see CLAUDE.md,
    "Core domain logic," for why: real tag data pulled from the live
    catalog showed a tags-based exclusion heuristic can't be built
    safely without real completions-failure evidence to validate it
    against first, and design_decisions.md already burned two
    heuristics on exactly this mistake. Every failure counts as a real
    error until that evidence exists.
    """
    return "counted_working" if success else "counted_error"
