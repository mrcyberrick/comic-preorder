-- Top Picks: one pick rule for the catalog rail and both customer emails, plus
-- the two new customer email settings.
-- Plan: docs/top-picks-emails-and-notification-settings.md (session S1).
-- STATUS: staging=PENDING | prod=PENDING
--
-- What the block does (one transaction):
--   (a) user_profiles.email_catalog boolean NOT NULL DEFAULT true  (new-catalog email)
--   (b) user_profiles.email_picks   boolean NOT NULL DEFAULT true  (Top Picks inside emails)
--   (c) widens the F182 self-update guard's allowlist from
--       {has_seen_welcome, email_arrivals} to add (a) and (b). Without this
--       every customer's own toggle save fails with 42501 (the S3b trap).
--   (d) public.get_top_picks(p_user_id uuid, p_limit integer): the Top picks
--       rule (plan § 3.1, decisions D3, D4, D5). Nothing calls it yet; the rail
--       moves to it in S2, the emails in S5.
--
-- Run order: STEP 0 on its own; if it reads as expected, the BEGIN..COMMIT
-- block; then the VERDICT; then the SMOKE. Staging first. Production only
-- before the S2 client promotion.

-- ── STEP 0: PRE-CHECK (changes nothing) ─────────────────────────────────────
SELECT
  EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'user_profiles'
      AND column_name = 'email_catalog')                             AS email_catalog_exists,
  EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'user_profiles'
      AND column_name = 'email_picks')                               AS email_picks_exists,
  (SELECT pg_get_functiondef(oid) LIKE '%ARRAY[''has_seen_welcome'', ''email_arrivals'']%'
     FROM pg_proc WHERE proname = 'user_profiles_guard_self_update'
      AND pronamespace = 'public'::regnamespace)                     AS guard_is_s3b_body,
  (SELECT pg_get_functiondef(oid) LIKE '%COUNT(*)%'
      AND pg_get_functiondef(oid) LIKE '%current_tenant_id()%'
     FROM pg_proc WHERE proname = 'get_popular_series'
      AND pronamespace = 'public'::regnamespace)                     AS popular_counts_rows,
  to_regprocedure('public.get_top_picks(uuid,integer)') IS NOT NULL  AS picks_fn_exists,
  (SELECT string_agg(slug, ',' ORDER BY slug) FROM public.tenants
    WHERE slug NOT LIKE 'pw-%')                                      AS tenants_here;
-- Expected: false, false, true, true, false, and tenants_here names the
-- project you meant (staging: demoshop,raysandjudys,riverside-comics;
-- production: comicstore,rjbookstop).
-- HALT if guard_is_s3b_body is false: the guard below would replace a body
-- that is not the one this file was written against. HALT if
-- popular_counts_rows is false: the popular tier below copies that count.

-- ── THE BLOCK ────────────────────────────────────────────────────────────────
BEGIN;

ALTER TABLE public.user_profiles ADD COLUMN email_catalog boolean NOT NULL DEFAULT true;
ALTER TABLE public.user_profiles ADD COLUMN email_picks   boolean NOT NULL DEFAULT true;

-- (c) The F182 guard. Unchanged from the S3b body except the allowlist.
CREATE OR REPLACE FUNCTION public.user_profiles_guard_self_update()
RETURNS trigger LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
BEGIN
  -- f182 guard, widened for S3b (email_arrivals) and the Top Picks plan (email_catalog, email_picks)
  IF current_user NOT IN ('anon', 'authenticated') THEN RETURN NEW; END IF;
  IF public.current_user_is_admin() IS TRUE THEN RETURN NEW; END IF;
  IF (to_jsonb(NEW) - ARRAY['has_seen_welcome', 'email_arrivals', 'email_catalog', 'email_picks'])
     IS DISTINCT FROM (to_jsonb(OLD) - ARRAY['has_seen_welcome', 'email_arrivals', 'email_catalog', 'email_picks']) THEN
    RAISE EXCEPTION 'That part of a profile can only be changed by a shop admin' USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END $$;

-- (d) The Top picks rule.
--
-- Returns at most p_limit rows (default 20, capped at 500) in rank order:
--   pick_id   the catalog row
--   pick_tier 'personal' (a series this customer has reserved before),
--             'popular'  (the store's most-reserved series this month),
--             'new1'     (a New #1 comic, D5; only after the first two run out, D3)
--   pick_rank 1..n
--
-- A row qualifies when it is in the tenant's latest catalog month, has a
-- series, is a standard cover, is not reserved by this customer (the exact
-- row, D4), its FOC has not passed, and the store's catalog visibility
-- settings (app_settings 'catalog_filters', read the way CatalogFilters.load()
-- and .hides() in app.js read it) do not hide it. One row per series: the
-- one whose FOC comes soonest.
--
-- Order: personal and popular ALTERNATE, personal first (Rick, 2026-10-09);
-- when one runs out the other fills. Personal series are ranked by how many
-- times this customer reserved them, popular series by the store's count
-- (get_popular_series()'s COUNT(*)), each with a name tie-breaker so the
-- order does not change between calls. New #1s fill any slots left (D3),
-- soonest FOC first.
--
-- Who may ask: an authenticated customer for themselves; an admin for a
-- customer of their own shop (the rail's view-as-customer path); the service
-- role (the mail functions) for anyone. EXECUTE is granted to authenticated
-- and service_role only, so a NULL auth.uid() here is the service role or
-- the SQL Editor.
--
-- "Today" is CURRENT_DATE (UTC). An import run in the evening Eastern, after
-- the UTC date turns, drops a title whose FOC is that same day a few hours
-- early. Conservative, accepted (plan § 3.1).
CREATE FUNCTION public.get_top_picks(p_user_id uuid DEFAULT NULL, p_limit integer DEFAULT 20)
RETURNS TABLE(pick_id uuid, pick_tier text, pick_rank integer)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller          uuid    := auth.uid();
  v_target          uuid    := COALESCE(p_user_id, auth.uid());
  v_limit           integer := LEAST(GREATEST(COALESCE(p_limit, 20), 1), 500);
  v_today           date    := CURRENT_DATE;
  v_tenant          uuid;
  v_month           text;
  v_raw             text;
  v_cfg             jsonb   := '{}'::jsonb;
  v_hidden          text[];
  v_show_std        boolean;
  v_show_restricted boolean;
  v_ratio_max       numeric;
  v_hide_foc        boolean;
  v_foc_mode        text;
  v_hide_zero       boolean;
BEGIN
  IF v_target IS NULL THEN
    RAISE EXCEPTION 'get_top_picks: no customer given' USING ERRCODE = '22023';
  END IF;

  -- A customer may ask only for themselves; anyone else must be an admin.
  IF v_caller IS NOT NULL AND v_caller <> v_target
     AND public.current_user_is_admin() IS NOT TRUE THEN
    RAISE EXCEPTION 'Not allowed to read another customer''s picks' USING ERRCODE = '42501';
  END IF;

  SELECT up.tenant_id INTO v_tenant FROM public.user_profiles up WHERE up.id = v_target;
  IF v_tenant IS NULL THEN RETURN; END IF;

  -- An admin may ask only within their own shop.
  IF v_caller IS NOT NULL AND v_caller <> v_target
     AND public.current_tenant_id() IS DISTINCT FROM v_tenant THEN
    RAISE EXCEPTION 'Not allowed to read another customer''s picks' USING ERRCODE = '42501';
  END IF;

  SELECT max(c.catalog_month) INTO v_month FROM public.catalog c WHERE c.tenant_id = v_tenant;
  IF v_month IS NULL THEN RETURN; END IF;

  -- The store's catalog visibility settings. Unreadable or absent means the
  -- defaults, as CatalogFilters.load() does.
  SELECT s.value INTO v_raw FROM public.app_settings s
   WHERE s.tenant_id = v_tenant AND s.key = 'catalog_filters';
  IF v_raw IS NOT NULL THEN
    BEGIN
      v_cfg := v_raw::jsonb;
      IF jsonb_typeof(v_cfg) IS DISTINCT FROM 'object' THEN v_cfg := '{}'::jsonb; END IF;
    EXCEPTION WHEN others THEN
      v_cfg := '{}'::jsonb;
    END;
  END IF;
  v_hidden := ARRAY(
    SELECT lower(btrim(x))
      FROM jsonb_array_elements_text(
             CASE WHEN jsonb_typeof(v_cfg -> 'publishersHidden') = 'array'
                  THEN v_cfg -> 'publishersHidden' ELSE '[]'::jsonb END) AS x
     WHERE btrim(x) <> '');
  v_show_std        := (v_cfg -> 'showStandard')   IS DISTINCT FROM 'false'::jsonb;  -- hidden only when exactly false
  v_show_restricted := (v_cfg -> 'showRestricted') IS DISTINCT FROM 'false'::jsonb;
  v_ratio_max       := CASE WHEN jsonb_typeof(v_cfg -> 'ratioMax') = 'number'
                            THEN (v_cfg ->> 'ratioMax')::numeric END;
  v_hide_foc        := CASE WHEN v_cfg ? 'hidePastFoc'
                            THEN (v_cfg ->> 'hidePastFoc') = 'true' ELSE true END;  -- default true
  v_foc_mode        := COALESCE(v_cfg ->> 'focMode', 'today');
  v_hide_zero       := (v_cfg ->> 'hideZeroPrice') = 'true';                         -- default false
  v_hide_zero       := COALESCE(v_hide_zero, false);

  RETURN QUERY
  WITH
  mine AS (          -- this customer's reservations, any month (D4: exact row)
    SELECT p.catalog_id FROM public.preorders p WHERE p.user_id = v_target
  ),
  signal AS (        -- series this customer has reserved before, and how often
    SELECT s.series_name, s.distributor, count(*) AS n
      FROM (
        SELECT rh.series_name, rh.distributor
          FROM public.reservation_history rh
         WHERE rh.user_id = v_target AND rh.tenant_id = v_tenant
           AND rh.series_name IS NOT NULL
        UNION ALL
        SELECT c.series_name, c.distributor
          FROM public.preorders p JOIN public.catalog c ON c.id = p.catalog_id
         WHERE p.user_id = v_target AND c.tenant_id = v_tenant
           AND c.series_name IS NOT NULL
      ) s
     GROUP BY s.series_name, s.distributor
  ),
  popular AS (       -- get_popular_series()'s count, for this tenant and month
    SELECT c.series_name, c.distributor, count(*) AS n
      FROM public.preorders p JOIN public.catalog c ON c.id = p.catalog_id
     WHERE c.catalog_month = v_month AND c.series_name IS NOT NULL AND c.tenant_id = v_tenant
     GROUP BY c.series_name, c.distributor
  ),
  eligible AS (      -- rows the customer could reserve now and would see
    SELECT c.id, c.series_name, c.distributor, c.title, c.format, c.foc_date, c.on_sale_date
      FROM public.catalog c
     WHERE c.tenant_id = v_tenant
       AND c.catalog_month = v_month
       AND c.series_name IS NOT NULL
       AND COALESCE(c.variant_type, '') IN ('', 'Standard', 'Primary Title')   -- isStandardCoverType(): '' counts
       AND NOT EXISTS (SELECT 1 FROM mine m WHERE m.catalog_id = c.id)
       AND NOT (c.foc_date IS NOT NULL AND c.foc_date < v_today)
       AND NOT (lower(btrim(COALESCE(c.publisher, ''))) = ANY (v_hidden))
       -- coverClassOf(): a ratio makes the row 'restricted', otherwise 'standard'
       AND CASE WHEN COALESCE(c.order_requirement, '') <> '' THEN
                  v_show_restricted
                  AND NOT (v_ratio_max IS NOT NULL
                           AND c.order_requirement ~ '^[0-9]+:[0-9]+$'
                           AND split_part(c.order_requirement, ':', 2)::numeric > v_ratio_max)
                ELSE v_show_std END
       AND NOT (v_hide_foc AND c.foc_date IS NOT NULL AND
                CASE WHEN v_foc_mode = 'today' THEN c.foc_date < v_today
                     ELSE to_char(c.foc_date, 'YYYY-MM') <= v_month END)
       AND NOT (v_hide_zero AND COALESCE(c.price_usd, 0) = 0)   -- JS Number(null) === 0
  ),
  per_series AS (    -- one row per series: the soonest FOC
    SELECT DISTINCT ON (e.series_name, e.distributor) e.id, e.series_name, e.distributor
      FROM eligible e
     ORDER BY e.series_name, e.distributor, e.foc_date NULLS LAST, e.on_sale_date NULLS LAST, e.id
  ),
  hist AS (          -- the two history tiers, each ranked within itself
    SELECT ps.id,
           CASE WHEN sg.series_name IS NOT NULL THEN 'personal' ELSE 'popular' END AS tier,
           row_number() OVER (
             PARTITION BY (sg.series_name IS NOT NULL)
             ORDER BY COALESCE(sg.n, 0) DESC, COALESCE(pp.n, 0) DESC, ps.series_name, ps.distributor
           ) AS k
      FROM per_series ps
      LEFT JOIN signal  sg ON sg.series_name = ps.series_name AND sg.distributor = ps.distributor
      LEFT JOIN popular pp ON pp.series_name = ps.series_name AND pp.distributor = ps.distributor
     WHERE sg.series_name IS NOT NULL OR pp.series_name IS NOT NULL
  ),
  new1 AS (          -- D5: New #1 comics, from series neither history tier holds
    SELECT DISTINCT ON (e.series_name, e.distributor) e.id, e.foc_date, e.title
      FROM eligible e
     WHERE e.format IN ('Periodical', 'Comic Book')
       AND e.title ~ '#\s*1(?![0-9])'
       AND e.title !~* '(FACSIMILE|BUNDLE|\(NET\)|^DF\y|SIGNED|BLANK|VIRGIN|PTG\y|PRINTING)'
       AND NOT EXISTS (SELECT 1 FROM signal sg
                        WHERE sg.series_name = e.series_name AND sg.distributor = e.distributor)
       AND NOT EXISTS (SELECT 1 FROM popular pp
                        WHERE pp.series_name = e.series_name AND pp.distributor = e.distributor)
     ORDER BY e.series_name, e.distributor, e.foc_date NULLS LAST, e.id
  ),
  ranked AS (
    SELECT h.id, h.tier, 0 AS grp, h.k,
           CASE h.tier WHEN 'personal' THEN 0 ELSE 1 END AS t
      FROM hist h
    UNION ALL
    SELECT n.id, 'new1', 1, row_number() OVER (ORDER BY n.foc_date NULLS LAST, n.title, n.id), 0
      FROM new1 n
  )
  SELECT r.id, r.tier, (row_number() OVER (ORDER BY r.grp, r.k, r.t))::integer
    FROM ranked r
   ORDER BY r.grp, r.k, r.t
   LIMIT v_limit;
END $$;

-- Supabase grants EXECUTE on a new function to anon and authenticated by
-- default; REVOKE ... FROM PUBLIC alone does not remove those (F124).
REVOKE ALL ON FUNCTION public.get_top_picks(uuid, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_top_picks(uuid, integer) TO authenticated, service_role;

COMMIT;

-- ── VERDICT (run on its own after the block) ────────────────────────────────
SELECT
  EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'user_profiles'
      AND column_name = 'email_catalog')                             AS email_catalog_exists,
  EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'user_profiles'
      AND column_name = 'email_picks')                               AS email_picks_exists,
  (SELECT count(*) FROM public.user_profiles
    WHERE email_catalog IS NOT TRUE OR email_picks IS NOT TRUE)      AS non_default_rows,
  (SELECT pg_get_functiondef(oid) LIKE '%''email_catalog'', ''email_picks''%'
     FROM pg_proc WHERE proname = 'user_profiles_guard_self_update'
      AND pronamespace = 'public'::regnamespace)                     AS guard_widened,
  to_regprocedure('public.get_top_picks(uuid,integer)') IS NOT NULL  AS picks_fn_exists,
  CASE WHEN to_regprocedure('public.get_top_picks(uuid,integer)') IS NOT NULL
       THEN has_function_privilege('anon', 'public.get_top_picks(uuid,integer)', 'EXECUTE') END
                                                                     AS anon_can_execute,
  CASE WHEN to_regprocedure('public.get_top_picks(uuid,integer)') IS NOT NULL
       THEN has_function_privilege('authenticated', 'public.get_top_picks(uuid,integer)', 'EXECUTE') END
                                                                     AS authenticated_can_execute,
  CASE WHEN to_regprocedure('public.get_top_picks(uuid,integer)') IS NOT NULL
       THEN has_function_privilege('service_role', 'public.get_top_picks(uuid,integer)', 'EXECUTE') END
                                                                     AS service_role_can_execute,
  (SELECT string_agg(slug, ',' ORDER BY slug) FROM public.tenants
    WHERE slug NOT LIKE 'pw-%')                                      AS tenants_here;
-- Expected: true, true, 0, true, true, false, true, true, and the project you
-- meant. Before the block this reads false, false, (error: no such column),
-- false, false, NULL, NULL, NULL, so a run that did not land cannot read as a
-- pass. If it errors on non_default_rows, the block did not run.

-- ── SMOKE (run on its own; read-only; no customer ids in the output) ────────
SELECT t.slug,
       count(*)                          AS active_customers,
       count(*) FILTER (WHERE x.n > 0)   AS with_picks,
       min(x.n)                          AS fewest,
       max(x.n)                          AS most,
       sum(x.personal)                   AS personal_picks,
       sum(x.popular)                    AS popular_picks,
       sum(x.new1)                       AS new1_picks
  FROM public.user_profiles up
  JOIN public.tenants t ON t.id = up.tenant_id
  CROSS JOIN LATERAL (
    SELECT count(*)                                        AS n,
           count(*) FILTER (WHERE g.pick_tier = 'personal') AS personal,
           count(*) FILTER (WHERE g.pick_tier = 'popular')  AS popular,
           count(*) FILTER (WHERE g.pick_tier = 'new1')     AS new1
      FROM public.get_top_picks(up.id, 20) g
  ) x
 WHERE up.is_admin IS NOT TRUE AND up.status = 'active' AND up.is_paper IS NOT TRUE
   AND t.slug NOT LIKE 'pw-%'
 GROUP BY t.slug
 ORDER BY t.slug;
-- Expected on production (S0, 2026-11-17): rjbookstop 21 active, all 21 with
-- picks, most = 20, new1_picks = 0 (every customer has 41+ history picks).
-- Staging has no S0 baseline; any tenant with active customers should show
-- with_picks = active_customers unless its catalog month is entirely past FOC.
