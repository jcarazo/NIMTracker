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

Standalone, local-only: no GitHub Actions, no Supabase. Reads
build.nvidia.com, writes one JSON report to disk.

Setup:
  pip install playwright
  playwright install chromium

Usage:
  python -m nimtracker.catalog_scraper
  python -m nimtracker.catalog_scraper --skip-details   # list page only
  python -m nimtracker.catalog_scraper --delay 2        # more polite
"""

import argparse
import json
import re
import sys
import time
from datetime import datetime, timezone

try:
    from playwright.sync_api import Page, sync_playwright
except ImportError:
    print("Missing dependency. Run: pip install playwright && playwright install chromium", file=sys.stderr)
    sys.exit(1)

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
        slug = model_el.get_attribute("href") if model_el else None
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
            "slug": slug,
            "description": description,
            "badges": badges,
            "tags": tags,
            "deprecation_days": deprecation,
            "is_free_endpoint": "Free Endpoint" in badges,
        })

    return results


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


def derive_api_model_id(slug: str) -> str:
    return slug.lstrip("/")


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


def scrape_detail(page: Page, slug: str, debug: bool = False) -> dict:
    url = f"{BASE_URL}{slug}"
    page.goto(url, wait_until="domcontentloaded", timeout=20000)
    # The catalog list's href for a card is not guaranteed to be the
    # model's canonical URL -- confirmed by direct observation: NVIDIA
    # 30x-redirects at least one card's slug to a different detail page.
    # Compare against where we actually land, not just the requested slug.
    resolved_slug = page.url.removeprefix(BASE_URL)
    redirected = resolved_slug != slug

    try:
        aside = page.wait_for_selector('aside[aria-label="Model information"]', timeout=15000)
        sidebar_result = {"has_specifications_sidebar": True}
    except Exception:
        if debug:
            safe_name = slug.strip("/").replace("/", "_")
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
    # catalog-list slug, so a redirect alone doesn't manufacture a
    # false mismatch between scraped and derived.
    derived = derive_api_model_id(resolved_slug)
    scraped = id_result.get("api_model_id_scraped")
    id_result["api_model_id_derived"] = derived
    id_result["api_model_id_mismatch"] = (scraped != derived) if scraped is not None else None
    id_result["resolved_slug"] = resolved_slug
    id_result["slug_redirected"] = redirected

    return {**sidebar_result, **id_result}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", default=DEFAULT_LIST_URL, help="Catalog list URL to scrape")
    parser.add_argument("--skip-details", action="store_true", help="Only scrape the list page, skip visiting each model's own detail page")
    parser.add_argument("--delay", type=float, default=1.5, help="Seconds between detail-page requests (default 1.5)")
    parser.add_argument("--headed", action="store_true", help="Run with a visible browser window (for debugging)")
    parser.add_argument("--debug-failures", action="store_true", help="On any 'no sidebar' result, save the raw page HTML to a file for inspection")
    parser.add_argument("--out", default=None)
    args = parser.parse_args()

    out_path = args.out or f"catalog_scrape_{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')}.json"

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=not args.headed)
        page = browser.new_page()

        print(f"Scraping list page: {args.url} ...")
        start = time.monotonic()
        results = scrape_list(page, args.url)
        print(f"Found {len(results)} models in {time.monotonic() - start:.1f}s.\n")

        if not args.skip_details:
            print(f"Visiting {len(results)} model detail pages, {args.delay}s delay between requests.\n")
            for i, m in enumerate(results, 1):
                print(f"[{i}/{len(results)}] {m['slug']} ...", end=" ", flush=True)
                # fresh page per visit -- avoids any accumulated hydration/
                # session state from reusing one page across many sequential
                # navigations, which is a plausible cause of false negatives
                detail_page = browser.new_page()
                detail = scrape_detail(detail_page, m["slug"], debug=args.debug_failures)
                detail_page.close()
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
        text_models = [r for r in results if r.get("is_text_completion_model")]
        non_text = [r for r in results if r.get("has_specifications_sidebar") and not r.get("is_text_completion_model")]
        no_sidebar = [r for r in results if not r.get("has_specifications_sidebar")]

        print(f"Text-completion models: {len(text_models)}")
        print(f"Non-text (has sidebar, output != Text): {len(non_text)}")
        print(f"No specifications sidebar (non-standard page): {len(no_sidebar)}")

        no_snippet = [r for r in results if not r.get("code_snippet_found")]
        no_match = [r for r in results if r.get("code_snippet_found") and r.get("api_model_id_scraped") is None and not r.get("api_model_id_ambiguous_matches")]
        ambiguous = [r for r in results if r.get("api_model_id_ambiguous_matches")]
        mismatches = [r for r in results if r.get("api_model_id_mismatch")]

        print(f"\napi_model_id: no code snippet found: {len(no_snippet)}")
        print(f"api_model_id: snippet found but no 'model' field matched: {len(no_match)}")
        print(f"api_model_id: ambiguous (multiple distinct 'model' values): {len(ambiguous)}")
        print(f"api_model_id: scraped != derived (mismatch): {len(mismatches)}")

        if no_snippet:
            print("\nNo code snippet:")
            for r in no_snippet:
                print(f"  {r['slug']}")

        if no_match:
            print("\nSnippet found, no 'model' field matched:")
            for r in no_match:
                print(f"  {r['slug']}")

        if ambiguous:
            print("\nAmbiguous 'model' field matches:")
            for r in ambiguous:
                print(f"  {r['slug']} -- {r['api_model_id_ambiguous_matches']}")

        if mismatches:
            print("\nMismatches (scraped vs. derived):")
            for r in mismatches:
                print(f"  {r['slug']} -- scraped={r['api_model_id_scraped']!r} derived={r['api_model_id_derived']!r}")

        redirected = [r for r in results if r.get("slug_redirected")]
        if redirected:
            print(f"\nCatalog-list slug redirected to a different detail page ({len(redirected)}):")
            for r in redirected:
                print(f"  {r['slug']} -> {r['resolved_slug']}")

        if non_text:
            print("\nNon-text models:")
            for r in non_text:
                print(f"  {r['slug']} -- output: {r['output_modalities']}")

        if no_sidebar:
            print("\nNo-sidebar models:")
            for r in no_sidebar:
                print(f"  {r['slug']}")

    if deprecating:
        print(f"\nDeprecation warnings found ({len(deprecating)}):")
        for r in deprecating:
            print(f"  {r['provider']} / {r['model_name']} — deprecating in {r['deprecation_days']}d")

    print(f"\nFull results saved to {out_path}")


if __name__ == "__main__":
    main()
