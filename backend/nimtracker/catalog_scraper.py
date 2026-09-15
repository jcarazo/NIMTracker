#!/usr/bin/env python3
"""
Catalog + detail-page scraper for build.nvidia.com's Free Endpoint models.

Phase 0 scope (model-identifier verification pass): in addition to the
list-page fields and the Specifications-sidebar heuristic fields (both
carried over from the reference script), this scrapes the literal
`model` value out of each model's own detail-page code snippet
(`pre[data-testid="highlighted-code"]`) -- the value NVIDIA's own docs
say to use when actually calling the API for that model. This is the
authoritative source for `api_model_id`; "slug minus leading slash" is
only a fallback for the rare page missing a snippet.

Confirmed by direct inspection (not assumed): the snippet's default tab
is already rendered in the DOM on page load -- no click needed -- but
its *code style* is not fixed across models. Some render a raw
`requests` call (`"model": "value"`, JSON-style); others render the
`openai` SDK style (`model="value"`, kwarg-style, no quotes on the key).
The extraction regex below matches both.

Phase 2 scope (catalog discovery job): adds retry-once (on both the
list scrape and each detail scrape -- a transient-looking failure gets
one retry before being accepted as real) and DB-backed fallback,
matching design_decisions.md's "Fallback strategy" section:
  - Total list-scrape failure -> the model table isn't touched this
    run at all; just record catalog_run.list_source = 'db_fallback'.
  - One model's detail-scrape failure -> fall back to its last-known
    DB row via find_model_by_href(), which also handles a model whose
    catalog-list href redirects to a different resolved slug (see
    model.catalog_href in db/schema.sql).
run_catalog_job() is the real entrypoint; scrape-only / JSON-dump mode
(no DB involved) still exists unchanged for ad-hoc manual scrapes.

Setup:
  pip install -e .
  playwright install chromium

Usage:
  python -m nimtracker.catalog_scraper                          # scrape-only, dumps JSON, no DB
  python -m nimtracker.catalog_scraper --skip-details            # list page only
  python -m nimtracker.catalog_scraper --delay 2                 # more polite
  python -m nimtracker.catalog_scraper --run-job --db-url <dsn>  # the real job: scrape + upsert into the DB
"""

import argparse
import json
import re
import sys
import time
from datetime import datetime, timezone

try:
    from playwright.sync_api import Browser, Page, sync_playwright
except ImportError:
    print("Missing dependency. Run: pip install playwright && playwright install chromium", file=sys.stderr)
    sys.exit(1)

from nimtracker import db

BASE_URL = "https://build.nvidia.com"
DEFAULT_LIST_URL = f"{BASE_URL}/models?filters=nimType%3Anim_type_preview&pageSize=96"

# Matches both `"model": "value"` (JSON-style) and `model="value"` /
# `model = "value"` (kwarg-style) -- confirmed necessary: kimi-k3 uses the
# first style, deepseek-v4-flash-0731 the second, on the *same* site.
MODEL_FIELD_RE = re.compile(r"""\bmodel["']?\s*[:=]\s*["']([^"']+)["']""")

# `pre[data-testid="highlighted-code"]` is not unique to the API code
# snippet -- confirmed by direct inspection: on "Experience"-tab pages
# with no Build tab (e.g. riva-translate-*, nemotron-3-embed-1b), NVIDIA
# reuses the same testid for the interactive demo's *output* box, which
# has no relation to the completions API call at all. Every genuine API
# snippet observed so far includes this literal placeholder; require it
# before trusting anything extracted from the element.
API_SNIPPET_MARKER = "NVIDIA_API_KEY"


class ScrapeFailed(Exception):
    """Raised for a transient-looking scrape failure -- navigation
    error, or landing on a known error page -- as opposed to a
    legitimate non-standard page (no sidebar, no snippet), which is
    real signal and returned normally, never raised.
    """


# Confirmed by direct observation in Phase 0: this specific redirect
# target is sometimes transient (one model loaded fine again moments
# later on manual recheck) and sometimes a real, persistent break (a
# different model stayed broken on repeat checks) -- worth a retry
# before concluding either way, never accepted on the first hit.
ERROR_PAGE_HREFS = {"/experience-unavailable"}


def scrape_list(page: Page, url: str) -> list[dict]:
    page.goto(url, wait_until="domcontentloaded", timeout=30000)
    page.wait_for_selector('[data-testid="nv-card-root"]', timeout=20000)

    prev_count = -1
    for _ in range(10):
        cards = page.query_selector_all('[data-testid="nv-card-root"]')
        count = len(cards)
        if count == prev_count:
            break
        prev_count = count
        page.wait_for_timeout(1000)

    cards = page.query_selector_all('[data-testid="nv-card-root"]')
    results = []

    for card in cards:
        provider_el = card.query_selector('a[data-nvtrack-nav-object="artifact-card-publisher-link"]')
        model_el = card.query_selector('a[data-nvtrack-nav-object="artifact-card"]')
        badge_els = card.query_selector_all('span.nv-badge')
        desc_el = card.query_selector('span.line-clamp-2')

        tag_els = card.query_selector_all('[data-testid="nv-tag-root"] span.inline-block')
        tags = sorted(set(t.text_content().strip() for t in tag_els if t.text_content().strip()))

        provider = provider_el.inner_text().strip() if provider_el else None
        model_name = model_el.inner_text().strip() if model_el else None
        # NOT a resolved slug -- the raw, as-scraped card href. Renamed
        # from "slug" (Phase 0) to "catalog_href" (Phase 2) once we
        # confirmed a card's href can redirect to a different resolved
        # slug on its own detail page -- see model.catalog_href in
        # db/schema.sql. Keeping the old name here would have kept
        # inviting exactly that confusion.
        catalog_href = model_el.get_attribute("href") if model_el else None
        description = desc_el.text_content().strip() if desc_el else None
        badges = [b.inner_text().strip() for b in badge_els]

        deprecation = None
        for b in badges:
            m = re.search(r"Deprecation in (\d+)d", b)
            if m:
                deprecation = int(m.group(1))

        results.append({
            "provider": provider,
            "model_name": model_name,
            "catalog_href": catalog_href,
            "description": description,
            "badges": badges,
            "tags": tags,
            "deprecation_days": deprecation,
            "is_free_endpoint": "Free Endpoint" in badges,
        })

    return results


def scrape_list_with_retry(browser: Browser, url: str, retries: int = 1) -> list[dict] | None:
    """Same retry-once discipline as the detail-page scraper, generalized
    to the list page -- there's no specific known "sometimes transient"
    error signal for the list page the way /experience-unavailable is
    for detail pages, so any exception here is treated as retry-worthy.
    Returns None if every attempt fails -- caller falls back to the DB.
    """
    last_error: Exception | None = None
    for _ in range(retries + 1):
        page = browser.new_page()
        try:
            return scrape_list(page, url)
        except Exception as e:
            last_error = e
        finally:
            page.close()
    print(f"list scrape failed after {retries + 1} attempt(s): {last_error}", file=sys.stderr)
    return None


def extract_dl_fields(aside) -> dict:
    """Generic extractor for the dt/dd pairs used by all three sidebar
    sections (Specifications, Capabilities, Model Availability) -- they
    share the same markup, so one function handles all of it.
    """
    fields = {}
    dts = aside.query_selector_all("dt")
    for dt in dts:
        label = dt.inner_text().strip()
        dt_id = dt.get_attribute("id")
        if not label or not dt_id:
            continue
        dd = aside.query_selector(f'dd[aria-labelledby="{dt_id}"]')
        value = dd.inner_text().strip() if dd else None
        fields[label] = value
    return fields


def derive_api_model_id(href: str) -> str:
    return href.lstrip("/")


def extract_api_model_id(page: Page) -> dict:
    """Pulls the literal `model` value out of the default-tab code
    snippet. Independent of the sidebar scrape -- a missing snippet
    shouldn't take down sidebar extraction or vice versa.
    """
    try:
        pre = page.wait_for_selector('pre[data-testid="highlighted-code"]', timeout=10000)
        snippet_text = pre.inner_text()
    except Exception:
        snippet_text = ""

    if API_SNIPPET_MARKER not in snippet_text:
        return {
            "code_snippet_found": False,
            "api_model_id_scraped": None,
        }

    matches = sorted(set(MODEL_FIELD_RE.findall(snippet_text)))

    if len(matches) == 1:
        return {
            "code_snippet_found": True,
            "api_model_id_scraped": matches[0],
        }
    if len(matches) == 0:
        return {
            "code_snippet_found": True,
            "api_model_id_scraped": None,
        }
    # More than one distinct value -- ambiguous, flag rather than guess.
    return {
        "code_snippet_found": True,
        "api_model_id_scraped": None,
        "api_model_id_ambiguous_matches": matches,
    }


def _scrape_detail_once(page: Page, catalog_href: str, debug: bool = False) -> dict:
    """One attempt. Raises ScrapeFailed for a transient-looking failure
    (navigation error, or a redirect to a known error page) -- caller
    decides whether to retry. Never raises for a legitimate
    non-standard page (no sidebar, no code snippet -- e.g. a
    translation/embedding "Experience"-tab demo page); that's real,
    stable signal, returned normally like any other result.
    """
    url = f"{BASE_URL}{catalog_href}"
    try:
        page.goto(url, wait_until="domcontentloaded", timeout=20000)
    except Exception as e:
        raise ScrapeFailed(f"navigation failed for {catalog_href}: {e}") from e

    # The catalog list's href for a card is not guaranteed to be the
    # model's canonical URL -- confirmed by direct observation: NVIDIA
    # 30x-redirects at least one card's href to a different detail page.
    # Compare against where we actually land, not just the requested href.
    resolved_slug = page.url.removeprefix(BASE_URL)
    if resolved_slug in ERROR_PAGE_HREFS:
        raise ScrapeFailed(f"{catalog_href} redirected to error page {resolved_slug}")

    redirected = resolved_slug != catalog_href

    try:
        aside = page.wait_for_selector('aside[aria-label="Model information"]', timeout=15000)
        sidebar_result = {"has_specifications_sidebar": True}
    except Exception:
        if debug:
            safe_name = catalog_href.strip("/").replace("/", "_")
            debug_path = f"debug_no_sidebar_{safe_name}.html"
            try:
                with open(debug_path, "w") as f:
                    f.write(page.content())
            except Exception:
                debug_path = None
        else:
            debug_path = None
        sidebar_result = {
            "has_specifications_sidebar": False,
            "output_modalities": None,
            "input_modalities": None,
            "is_text_completion_model": False,
            "debug_html_saved": debug_path,
        }
        aside = None

    if aside is not None:
        fields = extract_dl_fields(aside)
        output_modalities = fields.get("Output Modalities")
        is_text_completion = bool(output_modalities and "text" in output_modalities.lower())
        sidebar_result.update({
            "context_length": fields.get("Context Length"),
            "parameters": fields.get("Parameters"),
            "input_modalities": fields.get("Input Modalities"),
            "output_modalities": output_modalities,
            "function_calling": fields.get("Function Calling"),
            "structured_output": fields.get("Structured Output"),
            "reasoning": fields.get("Reasoning"),
            "is_text_completion_model": is_text_completion,
        })

    id_result = extract_api_model_id(page)

    # Derive from the resolved (post-redirect) slug -- the slug we
    # actually scraped the snippet from -- not the possibly-stale
    # catalog-list href, so a redirect alone doesn't manufacture a
    # false mismatch between scraped and derived.
    derived = derive_api_model_id(resolved_slug)
    scraped = id_result.get("api_model_id_scraped")
    id_result["api_model_id_derived"] = derived
    id_result["api_model_id_mismatch"] = (scraped != derived) if scraped is not None else None
    id_result["resolved_slug"] = resolved_slug
    id_result["slug_redirected"] = redirected

    return {**sidebar_result, **id_result}


def scrape_detail_with_retry(browser: Browser, catalog_href: str, debug: bool = False, retries: int = 1) -> dict | None:
    """Retries specifically on a transient-looking failure (navigation
    error, or a redirect to a known error page) -- never on a
    legitimate non-standard page, which _scrape_detail_once returns
    normally rather than raising. Returns None if every attempt fails --
    caller falls back to the DB via find_model_by_href().
    """
    last_error: Exception | None = None
    for _ in range(retries + 1):
        # Fresh page per attempt -- avoids any accumulated hydration/
        # session state from reusing one page across navigations, which
        # is a plausible cause of false negatives (same reasoning as the
        # original Phase 0 "fresh page per visit" choice, now also
        # applied across retries of the *same* model).
        page = browser.new_page()
        try:
            return _scrape_detail_once(page, catalog_href, debug=debug)
        except ScrapeFailed as e:
            last_error = e
        finally:
            page.close()
    print(f"  detail scrape failed after {retries + 1} attempt(s) for {catalog_href}: {last_error}", file=sys.stderr)
    return None


def find_model_by_href(conn, catalog_href: str) -> dict | None:
    """Look up a model's existing DB row from today's raw catalog-list
    href, for use when this run's detail scrape for it failed (so we
    don't have a fresh resolved slug to look up by directly).

    Two-step: try treating the href as if it were already the resolved
    slug (the common case -- a non-redirecting href already equals its
    own resolved slug), then fall back to a catalog_href match (the
    case a plain slug lookup can't reach: a model whose href redirects
    to a *different* resolved slug -- confirmed real, see
    model.catalog_href in db/schema.sql). Returns None only if neither
    matches -- genuinely never seen before.
    """
    row = db.get_model_by_slug(conn, derive_api_model_id(catalog_href))
    if row is not None:
        return row
    return db.get_model_by_catalog_href(conn, catalog_href)


def _build_model_row_from_live(list_row: dict, detail: dict) -> dict:
    """Detail scrape succeeded this run -- the resolved slug and every
    detail-page-sourced field are fresh and authoritative.
    """
    resolved = derive_api_model_id(detail["resolved_slug"])
    scraped = detail.get("api_model_id_scraped")
    if scraped is not None:
        api_model_id, api_model_id_source = scraped, "scraped_snippet"
    else:
        api_model_id, api_model_id_source = resolved, "derived_fallback"

    return {
        "slug": resolved,
        "provider": list_row["provider"],
        "model_name": list_row["model_name"],
        "description": list_row["description"],
        "tags": list_row["tags"],
        "is_free_endpoint": list_row["is_free_endpoint"],
        "deprecation_days": list_row["deprecation_days"],
        "catalog_href": list_row["catalog_href"],
        "output_modalities": detail.get("output_modalities"),
        "has_specifications_sidebar": detail.get("has_specifications_sidebar"),
        "is_text_completion_model": detail.get("is_text_completion_model"),
        "context_length": detail.get("context_length"),
        "parameters": detail.get("parameters"),
        "function_calling": detail.get("function_calling"),
        "structured_output": detail.get("structured_output"),
        "reasoning": detail.get("reasoning"),
        "detail_source": "live",
        "api_model_id": api_model_id,
        "api_model_id_source": api_model_id_source,
    }


def _build_model_row_from_fallback(list_row: dict, existing: dict) -> dict:
    """Detail scrape failed this run, but find_model_by_href() found the
    model's existing DB row. List-page-sourced fields (provider,
    model_name, description, tags, badges) still come from TODAY's
    fresh list scrape, since that succeeded independent of this one
    model's detail-page failure -- only the detail-page-sourced fields
    fall back to the stale DB row.
    """
    return {
        "slug": existing["slug"],  # the true resolved slug, not today's possibly-redirecting href
        "provider": list_row["provider"],
        "model_name": list_row["model_name"],
        "description": list_row["description"],
        "tags": list_row["tags"],
        "is_free_endpoint": list_row["is_free_endpoint"],
        "deprecation_days": list_row["deprecation_days"],
        "catalog_href": list_row["catalog_href"],
        "output_modalities": existing["output_modalities"],
        "has_specifications_sidebar": existing["has_specifications_sidebar"],
        "is_text_completion_model": existing["is_text_completion_model"],
        "context_length": existing["context_length"],
        "parameters": existing["parameters"],
        "function_calling": existing["function_calling"],
        "structured_output": existing["structured_output"],
        "reasoning": existing["reasoning"],
        "detail_source": "db_fallback",
        "api_model_id": existing["api_model_id"],
        "api_model_id_source": existing["api_model_id_source"],
    }


def _build_model_row_unknown(list_row: dict) -> dict:
    """Detail scrape failed AND no existing DB row was found -- a brand
    new model, never successfully scraped before. Insert it anyway with
    null heuristic fields rather than silently dropping it: a scrape
    failure must never hide a model's existence, the same principle
    design_decisions.md states for heuristics never gating testing,
    extended here to catalog membership itself.
    """
    catalog_href = list_row["catalog_href"]
    return {
        "slug": derive_api_model_id(catalog_href),
        "provider": list_row["provider"],
        "model_name": list_row["model_name"],
        "description": list_row["description"],
        "tags": list_row["tags"],
        "is_free_endpoint": list_row["is_free_endpoint"],
        "deprecation_days": list_row["deprecation_days"],
        "catalog_href": catalog_href,
        "output_modalities": None,
        "has_specifications_sidebar": None,
        "is_text_completion_model": None,
        "context_length": None,
        "parameters": None,
        "function_calling": None,
        "structured_output": None,
        "reasoning": None,
        "detail_source": "unknown",
        "api_model_id": derive_api_model_id(catalog_href),
        "api_model_id_source": "derived_fallback",
    }


def run_catalog_job(browser: Browser, conn, url: str = DEFAULT_LIST_URL, delay: float = 1.5, debug_failures: bool = False) -> dict:
    """The real Phase 2 job: scrape + upsert into the DB, one transaction
    for the whole run (atomic -- either the full refresh lands or none
    of it does). Caller owns the connection's lifecycle (open/commit-or-
    rollback/close); this function calls conn.commit() itself on every
    path since it's the unit of work, but doesn't open or close conn.

    On a total list-scrape failure (after retry): the model table is
    NOT touched at all this run. There's no fresh candidate list to
    upsert, and attempting 30+ individual detail-page navigations right
    after the list page itself failed is unlikely to do anything but
    generate more failures against a possibly-struggling site. Just
    record the fallback via catalog_run and stop.
    """
    list_results = scrape_list_with_retry(browser, url)

    if list_results is None:
        existing_count = db.count_models(conn)
        db.insert_catalog_run(conn, list_source="db_fallback", models_found_count=existing_count)
        conn.commit()
        return {
            "list_source": "db_fallback",
            "models_found_count": existing_count,
            "detail_live": 0,
            "detail_db_fallback": 0,
            "detail_unknown": 0,
        }

    summary = {
        "list_source": "live",
        "models_found_count": len(list_results),
        "detail_live": 0,
        "detail_db_fallback": 0,
        "detail_unknown": 0,
    }

    for i, list_row in enumerate(list_results, 1):
        catalog_href = list_row["catalog_href"]
        print(f"[{i}/{len(list_results)}] {catalog_href} ...", end=" ", flush=True)

        detail = scrape_detail_with_retry(browser, catalog_href, debug=debug_failures)

        if detail is not None:
            row = _build_model_row_from_live(list_row, detail)
            summary["detail_live"] += 1
            print("live")
        else:
            existing = find_model_by_href(conn, catalog_href)
            if existing is not None:
                row = _build_model_row_from_fallback(list_row, existing)
                summary["detail_db_fallback"] += 1
                print(f"db_fallback (existing: {existing['slug']})")
            else:
                row = _build_model_row_unknown(list_row)
                summary["detail_unknown"] += 1
                print("unknown (never seen before)")

        db.upsert_model(conn, row)

        if i < len(list_results):
            time.sleep(delay)

    db.insert_catalog_run(conn, list_source="live", models_found_count=len(list_results))
    conn.commit()
    return summary


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", default=DEFAULT_LIST_URL, help="Catalog list URL to scrape")
    parser.add_argument("--skip-details", action="store_true", help="Only scrape the list page, skip visiting each model's own detail page (ignored with --run-job)")
    parser.add_argument("--delay", type=float, default=1.5, help="Seconds between detail-page requests (default 1.5)")
    parser.add_argument("--headed", action="store_true", help="Run with a visible browser window (for debugging)")
    parser.add_argument("--debug-failures", action="store_true", help="On any 'no sidebar' result, save the raw page HTML to a file for inspection")
    parser.add_argument("--out", default=None, help="JSON output path (scrape-only mode; ignored with --run-job)")
    parser.add_argument("--run-job", action="store_true", help="Run the real catalog job: scrape + upsert into the DB (Phase 2), instead of scrape-only JSON-dump mode. Writes to whatever --db-url / SUPABASE_DB_URL points at -- point this at a local/test database, never at production without review.")
    parser.add_argument("--db-url", default=None, help="Postgres connection string for --run-job. Defaults to the SUPABASE_DB_URL env var if not given.")
    args = parser.parse_args()

    if args.run_job:
        with sync_playwright() as p:
            browser = p.chromium.launch(headless=not args.headed)
            with db.get_connection(args.db_url) as conn:
                summary = run_catalog_job(browser, conn, url=args.url, delay=args.delay, debug_failures=args.debug_failures)
            browser.close()

        print(f"\n--- Catalog job summary ---")
        print(f"list_source: {summary['list_source']}")
        print(f"models_found_count: {summary['models_found_count']}")
        print(f"detail scrapes -- live: {summary['detail_live']}, db_fallback: {summary['detail_db_fallback']}, unknown: {summary['detail_unknown']}")
        return

    out_path = args.out or f"catalog_scrape_{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')}.json"

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=not args.headed)

        print(f"Scraping list page: {args.url} ...")
        start = time.monotonic()
        results = scrape_list_with_retry(browser, args.url)
        if results is None:
            print("List scrape failed after retry, and scrape-only mode has no DB to fall back to. Aborting.", file=sys.stderr)
            browser.close()
            sys.exit(1)
        print(f"Found {len(results)} models in {time.monotonic() - start:.1f}s.\n")

        if not args.skip_details:
            print(f"Visiting {len(results)} model detail pages, {args.delay}s delay between requests.\n")
            for i, m in enumerate(results, 1):
                print(f"[{i}/{len(results)}] {m['catalog_href']} ...", end=" ", flush=True)
                detail = scrape_detail_with_retry(browser, m["catalog_href"], debug=args.debug_failures)

                if detail is None:
                    m.update({
                        "detail_scrape_failed": True,
                        "has_specifications_sidebar": None,
                        "code_snippet_found": False,
                        "api_model_id_scraped": None,
                    })
                    print("DETAIL SCRAPE FAILED (retries exhausted)")
                    if i < len(results):
                        time.sleep(args.delay)
                    continue

                m.update(detail)

                if detail["has_specifications_sidebar"]:
                    marker = "TEXT" if detail["is_text_completion_model"] else f"non-text ({detail['output_modalities']})"
                else:
                    marker = "NO SIDEBAR"

                if not detail.get("code_snippet_found"):
                    id_marker = "NO SNIPPET"
                elif detail.get("api_model_id_ambiguous_matches"):
                    id_marker = f"AMBIGUOUS {detail['api_model_id_ambiguous_matches']}"
                elif detail.get("api_model_id_scraped") is None:
                    id_marker = "NO MATCH IN SNIPPET"
                elif detail.get("api_model_id_mismatch"):
                    id_marker = f"MISMATCH scraped={detail['api_model_id_scraped']!r} derived={detail['api_model_id_derived']!r}"
                else:
                    id_marker = "id ok"

                redirect_marker = f" | REDIRECTED -> {detail['resolved_slug']}" if detail.get("slug_redirected") else ""
                print(f"{marker} | {id_marker}{redirect_marker}")

                if i < len(results):
                    time.sleep(args.delay)

        browser.close()

    with open(out_path, "w") as f:
        json.dump(results, f, indent=2)

    free_endpoint = [r for r in results if r["is_free_endpoint"]]
    deprecating = [r for r in results if r["deprecation_days"] is not None]

    print(f"\n--- Summary ---")
    print(f"Total cards found: {len(results)}")
    print(f"Tagged 'Free Endpoint': {len(free_endpoint)}")

    if not args.skip_details:
        failed = [r for r in results if r.get("detail_scrape_failed")]
        text_models = [r for r in results if r.get("is_text_completion_model")]
        non_text = [r for r in results if r.get("has_specifications_sidebar") and not r.get("is_text_completion_model")]
        no_sidebar = [r for r in results if not r.get("has_specifications_sidebar") and not r.get("detail_scrape_failed")]

        print(f"Detail scrape failed (retries exhausted): {len(failed)}")
        print(f"Text-completion models: {len(text_models)}")
        print(f"Non-text (has sidebar, output != Text): {len(non_text)}")
        print(f"No specifications sidebar (non-standard page): {len(no_sidebar)}")

        no_snippet = [r for r in results if not r.get("code_snippet_found") and not r.get("detail_scrape_failed")]
        no_match = [r for r in results if r.get("code_snippet_found") and r.get("api_model_id_scraped") is None and not r.get("api_model_id_ambiguous_matches")]
        ambiguous = [r for r in results if r.get("api_model_id_ambiguous_matches")]
        mismatches = [r for r in results if r.get("api_model_id_mismatch")]

        print(f"\napi_model_id: no code snippet found: {len(no_snippet)}")
        print(f"api_model_id: snippet found but no 'model' field matched: {len(no_match)}")
        print(f"api_model_id: ambiguous (multiple distinct 'model' values): {len(ambiguous)}")
        print(f"api_model_id: scraped != derived (mismatch): {len(mismatches)}")

        if failed:
            print("\nDetail scrape failed:")
            for r in failed:
                print(f"  {r['catalog_href']}")

        if no_snippet:
            print("\nNo code snippet:")
            for r in no_snippet:
                print(f"  {r['catalog_href']}")

        if no_match:
            print("\nSnippet found, no 'model' field matched:")
            for r in no_match:
                print(f"  {r['catalog_href']}")

        if ambiguous:
            print("\nAmbiguous 'model' field matches:")
            for r in ambiguous:
                print(f"  {r['catalog_href']} -- {r['api_model_id_ambiguous_matches']}")

        if mismatches:
            print("\nMismatches (scraped vs. derived):")
            for r in mismatches:
                print(f"  {r['catalog_href']} -- scraped={r['api_model_id_scraped']!r} derived={r['api_model_id_derived']!r}")

        redirected = [r for r in results if r.get("slug_redirected")]
        if redirected:
            print(f"\nCatalog-list href redirected to a different detail page ({len(redirected)}):")
            for r in redirected:
                print(f"  {r['catalog_href']} -> {r['resolved_slug']}")

        if non_text:
            print("\nNon-text models:")
            for r in non_text:
                print(f"  {r['catalog_href']} -- output: {r['output_modalities']}")

        if no_sidebar:
            print("\nNo-sidebar models:")
            for r in no_sidebar:
                print(f"  {r['catalog_href']}")

    if deprecating:
        print(f"\nDeprecation warnings found ({len(deprecating)}):")
        for r in deprecating:
            print(f"  {r['provider']} / {r['model_name']} — deprecating in {r['deprecation_days']}d")

    print(f"\nFull results saved to {out_path}")


if __name__ == "__main__":
    main()
