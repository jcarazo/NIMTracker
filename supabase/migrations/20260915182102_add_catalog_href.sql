-- Adds model.catalog_href -- see db/schema.sql for the full rationale.
--
-- Short version: the catalog job's fallback lookup, when a model's
-- detail-page scrape fails on a given run, only has today's raw
-- catalog-list href to search with -- not the resolved slug, which we
-- only learn by successfully navigating to the detail page (exactly
-- what failed). For a model whose href redirects to a different
-- resolved slug (confirmed real: '/nvidia/ising-calibration-1-35b-a3b'
-- -> 'nvidia/ising-calibration-1.5-31b'), a slug-only fallback lookup
-- never matches its existing row, so the catalog job would insert a
-- second, duplicate row for the same model instead of updating the
-- existing one.
--
-- Nullable, no default, no backfill needed -- existing rows simply have
-- no known catalog_href until their next successful list scrape
-- populates it, which is harmless: the fallback lookup this column
-- exists for only matters on a FUTURE detail-scrape failure, by which
-- point a normal run will already have set it.

alter table model add column catalog_href text;
