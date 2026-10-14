-- STATUS: IN PROGRESS | staging=APPLIED 2026-10-14 | prod=PENDING | findings=none (docs/facebook-weekly-post.md § 3b, § 4.6)
-- Weekly Facebook post: the three "spotlight" covers for a shop's week, for the
-- composed image the post-facebook job builds in mrcyberrick/weekly-pull-feed.
--
-- WHY A NEW FUNCTION: get_pull_feed_week (F135) deliberately returns no
-- quantities, and that stays true. The spotlight needs a ranking by copies
-- received, so this function does the ranking INSIDE the database and returns
-- only the result.
--
--   RETURNS: title, cover_url, series_name   (at most 3 rows, sorted by TITLE)
--   NEVER:   quantity, price_usd, a rank, item_code, upc, catalog_id, tenant_id, id
--
-- EXPOSURE, and the two limits Rick chose on 2026-10-14 (plan § 3b, "go with b&c"):
--   (b) It answers ONLY for the week containing today (UTC) and the week before.
--       Any other p_week_start raises 22023 naming the two allowed Mondays, so a
--       shop's history cannot be pulled.
--   (c) It returns the three in TITLE order, with no rank column, and takes NO
--       limit argument (a p_limit = 1 call would have revealed the #1 title).
--   What remains visible to anyone with the public anon key: which three titles
--   were spotlighted this week or last - exactly what the public post shows.
--
-- THE RULE (plan § 3a):
--   * rows of the week with a cover_url, this tenant only (catalog joined on the
--     same tenant, F164)
--   * group by series (coalesce(series_name, title)); rank series by TOTAL copies
--     received that week across all of the series' covers, ties by series name
--   * top 3 series; for each, show ONE cover: a standard cover first
--     (variant_type null / 'Standard' / 'Primary Title'), then the cover with the
--     most copies, then title, then cover_url (fully deterministic, F162)
--   * output ORDER BY title, cover_url
--
-- Week rule: Monday-to-Sunday, the same as get_pull_feed_week and the builder's
-- weekRange(). date_trunc('week', ...) in Postgres returns the ISO Monday.
-- Supabase's CURRENT_DATE is UTC, the same clock the job uses (todayUTC()).
--
-- Rollback: additive and unreferenced until the post-facebook job ships.
--   DROP FUNCTION public.get_pull_feed_spotlight(text, date);
--
-- Run order: STAGING first (slug 'raysandjudys'), then PRODUCTION (slug
-- 'rjbookstop'; the job reads production). Paste each section separately and
-- read its result: the SQL Editor shows only the last statement's output.

-- =====================================================================
-- PRE-FLIGHT (read-only) -- ONE statement.
-- =====================================================================
SELECT
  (SELECT count(*) FROM pg_proc
    WHERE pronamespace = 'public'::regnamespace
      AND proname = 'get_pull_feed_spotlight')                     AS name_taken,
  date_trunc('week', CURRENT_DATE)::date                            AS this_week_monday,
  (SELECT count(*) FROM public.weekly_shipment
    WHERE on_sale_date BETWEEN date_trunc('week', CURRENT_DATE)::date
                           AND date_trunc('week', CURRENT_DATE)::date + 6) AS this_week_rows,
  (SELECT string_agg(slug, ', ' ORDER BY slug) FROM public.tenants)  AS tenant_slugs;
-- EXPECTED: name_taken = 0; this_week_monday = the Monday of this week;
--   production this_week_rows > 0 once the week's shipment import has run
--   (2026-10-14: 119); staging may be 0. tenant_slugs: production
--   'comicstore, rjbookstop'; staging 'raysandjudys' (plus any pw-* fixtures).
-- STOP if name_taken > 0.

-- =====================================================================
-- MIGRATION
-- =====================================================================
BEGIN;

CREATE OR REPLACE FUNCTION public.get_pull_feed_spotlight(p_slug text, p_week_start date)
  RETURNS TABLE (title text, cover_url text, series_name text)
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path = public, pg_temp
  AS $$
#variable_conflict use_column
DECLARE
  v_this_week date := date_trunc('week', CURRENT_DATE)::date;
BEGIN
  IF p_week_start IS NULL OR p_week_start NOT IN (v_this_week, v_this_week - 7) THEN
    RAISE EXCEPTION 'get_pull_feed_spotlight: p_week_start must be % (this week) or % (last week)',
      v_this_week, v_this_week - 7
      USING ERRCODE = '22023';
  END IF;

  RETURN QUERY
  WITH wk AS (
    SELECT ws.title,
           ws.cover_url,
           c.series_name,
           coalesce(c.series_name, ws.title) AS series_key,
           ws.quantity,
           (c.variant_type IS NULL OR c.variant_type IN ('Standard', 'Primary Title')) AS is_standard
    FROM   public.tenants t
    JOIN   public.weekly_shipment ws ON ws.tenant_id = t.id
    LEFT   JOIN public.catalog c
           ON c.id = ws.catalog_id AND c.tenant_id = ws.tenant_id
    WHERE  t.slug = p_slug
      AND  ws.on_sale_date >= p_week_start
      AND  ws.on_sale_date <= p_week_start + 6
      AND  ws.cover_url IS NOT NULL
  ),
  top_series AS (
    SELECT series_key
    FROM   wk
    GROUP  BY series_key
    ORDER  BY sum(quantity) DESC, series_key
    LIMIT  3
  ),
  covers AS (
    SELECT wk.title, wk.cover_url, wk.series_name, wk.series_key,
           sum(wk.quantity)     AS qty,
           bool_or(wk.is_standard) AS is_standard
    FROM   wk JOIN top_series USING (series_key)
    GROUP  BY wk.title, wk.cover_url, wk.series_name, wk.series_key
  ),
  pick AS (
    SELECT DISTINCT ON (series_key) title, cover_url, series_name
    FROM   covers
    ORDER  BY series_key, is_standard DESC, qty DESC, title, cover_url
  )
  SELECT pick.title, pick.cover_url, pick.series_name
  FROM   pick
  ORDER  BY pick.title, pick.cover_url;
END
$$;

REVOKE ALL ON FUNCTION public.get_pull_feed_spotlight(text, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_pull_feed_spotlight(text, date) TO anon, authenticated;

COMMIT;

-- =====================================================================
-- VERIFY -- paste this whole section at once. The last statement returns ONE
-- row; read `verdict` first.
--
--   EXPECTED: verdict starts with 'OK - '. On production this week (2026-10-14)
--   slug = rjbookstop, picks = 3, and `spotlight` lists three titles from three
--   different series, which equal the series in `independent_top3`.
--   On staging 'OK (structure) - spotlight NOT exercised' is fine if staging
--   has no shipment rows for this week.
--   FAILURE: any verdict starting 'FAIL - ', or error 42883 (the function does
--   not exist: the migration did not land).
-- =====================================================================
DROP TABLE IF EXISTS pg_temp.fbs_probe;
CREATE TEMP TABLE fbs_probe (probe text, refused boolean, msg text);

DO $$
DECLARE
  v_slug text := coalesce(
    (SELECT slug FROM public.tenants WHERE slug = 'rjbookstop'),
    (SELECT slug FROM public.tenants WHERE slug = 'raysandjudys'));
  v_mon  date := date_trunc('week', CURRENT_DATE)::date;
BEGIN
  -- (b): three weeks back must be refused
  BEGIN
    PERFORM * FROM public.get_pull_feed_spotlight(v_slug, v_mon - 21);
    INSERT INTO fbs_probe VALUES ('3 weeks back', false, 'returned without error');
  EXCEPTION WHEN invalid_parameter_value THEN
    INSERT INTO fbs_probe VALUES ('3 weeks back', true, SQLERRM);
  END;
  -- (b): a non-Monday inside this week must be refused too
  BEGIN
    PERFORM * FROM public.get_pull_feed_spotlight(v_slug, v_mon + 1);
    INSERT INTO fbs_probe VALUES ('this Tuesday', false, 'returned without error');
  EXCEPTION WHEN invalid_parameter_value THEN
    INSERT INTO fbs_probe VALUES ('this Tuesday', true, SQLERRM);
  END;
  -- (b): last week's Monday must be ALLOWED
  BEGIN
    PERFORM * FROM public.get_pull_feed_spotlight(v_slug, v_mon - 7);
    INSERT INTO fbs_probe VALUES ('last week', false, 'allowed');
  EXCEPTION WHEN invalid_parameter_value THEN
    INSERT INTO fbs_probe VALUES ('last week', true, SQLERRM);
  END;
END $$;

WITH fn AS (
  SELECT p.oid, p.prosecdef, p.pronargs, p.proconfig,
         pg_get_function_result(p.oid) AS result_sig
  FROM   pg_proc p
  WHERE  p.pronamespace = 'public'::regnamespace
    AND  p.proname = 'get_pull_feed_spotlight'
),
ctx AS (
  SELECT coalesce((SELECT slug FROM public.tenants WHERE slug = 'rjbookstop'),
                  (SELECT slug FROM public.tenants WHERE slug = 'raysandjudys')) AS slug,
         date_trunc('week', CURRENT_DATE)::date AS mon
),
got AS (
  SELECT s.title, s.series_name, s.n
  FROM   ctx, public.get_pull_feed_spotlight(ctx.slug, ctx.mon)
         WITH ORDINALITY AS s(title, cover_url, series_name, n)
),
indep AS (   -- the ranking computed a second, simpler way
  SELECT coalesce(c.series_name, ws.title) AS series_key
  FROM   ctx
  JOIN   public.tenants t ON t.slug = ctx.slug
  JOIN   public.weekly_shipment ws ON ws.tenant_id = t.id
  LEFT   JOIN public.catalog c ON c.id = ws.catalog_id AND c.tenant_id = ws.tenant_id
  WHERE  ws.on_sale_date BETWEEN ctx.mon AND ctx.mon + 6
    AND  ws.cover_url IS NOT NULL
  GROUP  BY 1
  ORDER  BY sum(ws.quantity) DESC, 1
  LIMIT  3
),
wkstd AS (   -- every covered row this week, with whether it is a standard cover
  SELECT ws.title,
         coalesce(c.series_name, ws.title) AS series_key,
         (c.variant_type IS NULL OR c.variant_type IN ('Standard', 'Primary Title')) AS is_standard
  FROM   ctx
  JOIN   public.tenants t ON t.slug = ctx.slug
  JOIN   public.weekly_shipment ws ON ws.tenant_id = t.id
  LEFT   JOIN public.catalog c ON c.id = ws.catalog_id AND c.tenant_id = ws.tenant_id
  WHERE  ws.on_sale_date BETWEEN ctx.mon AND ctx.mon + 6
    AND  ws.cover_url IS NOT NULL
),
v AS (
  SELECT
    (SELECT count(*) FROM fn)                                             AS fn_count,
    (SELECT bool_and(prosecdef) FROM fn)                                  AS definer_ok,
    (SELECT bool_and(pronargs = 2) FROM fn)                               AS two_args_only,
    (SELECT bool_and(proconfig::text LIKE '%search_path=public%') FROM fn) AS search_path_ok,
    (SELECT bool_and(result_sig = 'TABLE(title text, cover_url text, series_name text)') FROM fn) AS projection_ok,
    (SELECT bool_and(has_function_privilege('anon', oid, 'EXECUTE')) FROM fn)          AS anon_exec,
    (SELECT bool_and(has_function_privilege('authenticated', oid, 'EXECUTE')) FROM fn) AS authenticated_exec,
    (SELECT NOT bool_or(has_function_privilege('public', oid, 'EXECUTE')) FROM fn)     AS public_revoked,
    (SELECT slug FROM ctx)                                                AS slug,
    (SELECT mon FROM ctx)                                                 AS week_start,
    (SELECT count(*) FROM got)                                            AS picks,
    (SELECT count(DISTINCT coalesce(series_name, title)) FROM got)        AS distinct_series,
    (SELECT coalesce(array_agg(title ORDER BY n) = array_agg(title ORDER BY title, n), true) FROM got) AS title_ordered,
    (SELECT string_agg(title, ' | ' ORDER BY n) FROM got)                 AS spotlight,
    (SELECT string_agg(series_key, ' | ' ORDER BY series_key) FROM indep) AS independent_top3,
    (SELECT coalesce(array_agg(coalesce(series_name, title) ORDER BY coalesce(series_name, title)), '{}') FROM got)
      = (SELECT coalesce(array_agg(series_key ORDER BY series_key), '{}') FROM indep) AS matches_independent,
    (SELECT count(*) FROM got g
      WHERE EXISTS (SELECT 1 FROM wkstd s WHERE s.series_key = coalesce(g.series_name, g.title) AND s.is_standard)
        AND NOT EXISTS (SELECT 1 FROM wkstd s WHERE s.title = g.title AND s.is_standard)) AS variant_picked_over_standard,
    (SELECT refused FROM fbs_probe WHERE probe = '3 weeks back')          AS refused_3_weeks_back,
    (SELECT refused FROM fbs_probe WHERE probe = 'this Tuesday')          AS refused_non_monday,
    (SELECT NOT refused FROM fbs_probe WHERE probe = 'last week')         AS allowed_last_week
)
SELECT v.*,
  CASE
    WHEN fn_count <> 1             THEN 'FAIL - function missing or duplicated'
    WHEN NOT definer_ok            THEN 'FAIL - not SECURITY DEFINER'
    WHEN NOT two_args_only         THEN 'FAIL - takes other than exactly (p_slug, p_week_start): a limit argument would expose the #1 title'
    WHEN NOT search_path_ok        THEN 'FAIL - search_path not pinned to public'
    WHEN NOT projection_ok         THEN 'FAIL - projection is not exactly title, cover_url, series_name (no rank, no quantity)'
    WHEN NOT anon_exec             THEN 'FAIL - anon cannot EXECUTE (the Actions job would get 401)'
    WHEN NOT authenticated_exec    THEN 'FAIL - authenticated cannot EXECUTE'
    WHEN NOT public_revoked        THEN 'FAIL - PUBLIC still holds EXECUTE'
    WHEN NOT refused_3_weeks_back  THEN 'FAIL - a week three weeks back was answered: limit (b) is not enforced'
    WHEN NOT refused_non_monday    THEN 'FAIL - a non-Monday date was answered'
    WHEN NOT allowed_last_week     THEN 'FAIL - last week was refused: limit (b) is too strict'
    WHEN picks > 3                 THEN 'FAIL - more than 3 rows returned'
    WHEN picks <> distinct_series  THEN 'FAIL - a series appears twice'
    WHEN NOT title_ordered         THEN 'FAIL - rows are not in title order: limit (c) is not enforced'
    WHEN picks = 0                 THEN 'OK (structure) - spotlight NOT exercised: no covered shipment rows this week'
    WHEN NOT matches_independent   THEN 'FAIL - the three series differ from the independently computed top 3'
    WHEN variant_picked_over_standard > 0 THEN 'FAIL - a variant cover was shown although the series has a standard cover this week'
    ELSE 'OK - spotlight RPC present, SECURITY DEFINER, anon-callable, no rank or counts, recent weeks only, title order, top 3 match'
  END AS verdict
FROM v;
