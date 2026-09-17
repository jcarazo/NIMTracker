#!/usr/bin/env python3
"""
Hourly completions sweep (Phase 3): one real chat-completions call per
catalog-listed model, unconditionally -- no heuristic gates testing
(design_decisions.md, "Model discovery & testing pipeline"). Classifies
each result via resolution.py and writes one `execution` row + one
`result` row per model per sweep, in one atomic transaction.

Deliberately NO in-run retries, for anything -- the opposite of Phase
2's catalog job. A `timeout`, `rate_limited` (429), or `server_error`
(5xx) is recorded immediately, once. Retrying within the same run risks
manufacturing a false "working" data point for a model that's
genuinely struggling right now; the next hourly run IS the retry, on
the natural cadence (design_decisions.md, "Hourly sweep parameters").

Every completions call runs to completion BEFORE any DB connection is
touched -- unlike the catalog job, this one never needs to read from
the DB mid-run, so there's no reason to hold a connection open for the
several-minutes duration of the network calls.

Setup:
  pip install -e .

Usage:
  python -m nimtracker.completions_probe --db-url <dsn>
"""

import argparse
import os
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone

import httpx

from nimtracker import db
from nimtracker.resolution import classify_error, resolve

API_URL = "https://integrate.api.nvidia.com/v1/chat/completions"
DEFAULT_PROMPT = "Write a Python function that checks if a number is prime and returns True or False"
DEFAULT_MAX_TOKENS = 500
TIMEOUT_SECONDS = 240.0
CONCURRENCY = 3
ERROR_BODY_MAX_LEN = 500


def call_model(client: httpx.Client, api_key: str, api_model_id: str) -> dict:
    """One attempt, no retries. Returns every `result` field except
    execution_id/model_slug/resolution, which the caller fills in.
    """
    payload = {
        "model": api_model_id,
        "messages": [{"role": "user", "content": DEFAULT_PROMPT}],
        "max_tokens": DEFAULT_MAX_TOKENS,
    }

    start = time.monotonic()
    try:
        resp = client.post(API_URL, json=payload, headers={"Authorization": f"Bearer {api_key}"})
        elapsed = time.monotonic() - start

        if resp.status_code >= 400:
            body_text = resp.text
            return {
                "success": False,
                "error_category": classify_error(resp.status_code, body_text),
                "error_body": body_text[:ERROR_BODY_MAX_LEN],
                "response_time_s": round(elapsed, 2),
                "completion_tokens": None,
                "prompt_tokens": None,
                "tokens_per_sec": None,
                "response_text": None,
            }

        body = resp.json()
        choices = body.get("choices", [])
        content = choices[0].get("message", {}).get("content", "") if choices else ""
        usage = body.get("usage", {})
        completion_tokens = usage.get("completion_tokens", 0)

        if not content:
            return {
                "success": False,
                "error_category": "empty_response",
                "error_body": None,
                "response_time_s": round(elapsed, 2),
                "completion_tokens": completion_tokens,
                "prompt_tokens": usage.get("prompt_tokens"),
                "tokens_per_sec": None,
                "response_text": None,
            }

        return {
            "success": True,
            "error_category": None,
            "error_body": None,
            "response_time_s": round(elapsed, 2),
            "completion_tokens": completion_tokens,
            "prompt_tokens": usage.get("prompt_tokens"),
            "tokens_per_sec": round(completion_tokens / elapsed, 1) if elapsed > 0 else None,
            "response_text": content,
        }

    except httpx.TimeoutException:
        elapsed = time.monotonic() - start
        return {
            "success": False,
            "error_category": "timeout",
            "error_body": None,
            "response_time_s": round(elapsed, 2),
            "completion_tokens": None,
            "prompt_tokens": None,
            "tokens_per_sec": None,
            "response_text": None,
        }

    except httpx.RequestError as e:
        elapsed = time.monotonic() - start
        return {
            "success": False,
            "error_category": "other",
            "error_body": str(e)[:ERROR_BODY_MAX_LEN],
            "response_time_s": round(elapsed, 2),
            "completion_tokens": None,
            "prompt_tokens": None,
            "tokens_per_sec": None,
            "response_text": None,
        }

    except Exception as e:
        # Anything else (e.g. a malformed JSON body on a 2xx response) --
        # never let one bad response take down the whole sweep. Nothing
        # is written to the DB until every model has been attempted, so
        # an uncaught exception here would lose the entire run's data,
        # not just this one model's.
        elapsed = time.monotonic() - start
        return {
            "success": False,
            "error_category": "other",
            "error_body": str(e)[:ERROR_BODY_MAX_LEN],
            "response_time_s": round(elapsed, 2),
            "completion_tokens": None,
            "prompt_tokens": None,
            "tokens_per_sec": None,
            "response_text": None,
        }


def run_completions_sweep(conn, api_key: str, concurrency: int = CONCURRENCY, timeout: float = TIMEOUT_SECONDS) -> dict:
    models = db.get_all_models(conn)
    started_at = datetime.now(timezone.utc)

    results = []
    with httpx.Client(timeout=timeout) as client:
        with ThreadPoolExecutor(max_workers=concurrency) as executor:
            futures = {
                executor.submit(call_model, client, api_key, m["api_model_id"]): m
                for m in models
            }
            for i, future in enumerate(as_completed(futures), 1):
                m = futures[future]
                call_result = future.result()
                results.append((m, call_result))
                status = "OK" if call_result["success"] else f"FAIL ({call_result['error_category']})"
                print(f"[{i}/{len(models)}] {m['slug']} ... {status}")

    resolved = [(m, r, resolve(r["success"])) for m, r in results]
    tested = [(m, r) for m, r, res in resolved if res != "excluded_non_text"]
    succeeded = [(m, r) for m, r in tested if r["success"]]

    fastest_model_slug = None
    fastest_response_time_s = None
    if succeeded:
        m, r = min(succeeded, key=lambda pair: pair[1]["response_time_s"])
        fastest_model_slug = m["slug"]
        fastest_response_time_s = r["response_time_s"]

    execution_id = db.insert_execution(conn, {
        "started_at": started_at,
        "models_tested_count": len(tested),
        "models_succeeded_count": len(succeeded),
        "fastest_model_slug": fastest_model_slug,
        "fastest_response_time_s": fastest_response_time_s,
    })

    for m, r, res in resolved:
        db.insert_result(conn, {
            "execution_id": execution_id,
            "model_slug": m["slug"],
            "success": r["success"],
            "error_category": r["error_category"],
            "error_body": r["error_body"],
            "response_time_s": r["response_time_s"],
            "completion_tokens": r["completion_tokens"],
            "prompt_tokens": r["prompt_tokens"],
            "tokens_per_sec": r["tokens_per_sec"],
            "response_text": r["response_text"],
            "resolution": res,
        })
        # last_seen_working_at / delisted_at / delisted_reason -- the
        # fields model.slug's own schema comment says this job owns.
        # Found missing entirely (never written by any prior code) while
        # building Phase 5's Models table, which is the first consumer
        # that reads last_seen_working_at. See db.update_model_lifecycle.
        db.update_model_lifecycle(
            conn,
            m["slug"],
            success=r["success"],
            error_category=r["error_category"],
            as_of=started_at,
            delisted_reason=r["error_body"] if r["error_category"] == "removed" else None,
        )

    conn.commit()

    return {
        "models_tested_count": len(tested),
        "models_succeeded_count": len(succeeded),
        "fastest_model_slug": fastest_model_slug,
        "fastest_response_time_s": fastest_response_time_s,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--db-url", default=None, help="Postgres connection string. Defaults to the SUPABASE_DB_URL env var if not given.")
    parser.add_argument("--concurrency", type=int, default=CONCURRENCY)
    parser.add_argument("--timeout", type=float, default=TIMEOUT_SECONDS)
    args = parser.parse_args()

    api_key = os.environ.get("NIM_API_KEY")
    if not api_key:
        print("Set NIM_API_KEY in the environment.", file=sys.stderr)
        sys.exit(1)

    with db.get_connection(args.db_url) as conn:
        summary = run_completions_sweep(conn, api_key, concurrency=args.concurrency, timeout=args.timeout)

    print(f"\n--- Completions sweep summary ---")
    print(f"models_tested_count: {summary['models_tested_count']}")
    print(f"models_succeeded_count: {summary['models_succeeded_count']}")
    print(f"fastest: {summary['fastest_model_slug']} ({summary['fastest_response_time_s']}s)")


if __name__ == "__main__":
    main()
