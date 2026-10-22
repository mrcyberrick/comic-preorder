#!/usr/bin/env bash
# G-J post-check: anon table reads must be 401 (42501); anon RPCs must still answer 200.
# Usage: gj-anon-probe.sh staging|prod   (run from the comic-preorder repo root)
set -u
env=${1:?staging|prod}
if [ "$env" = prod ]; then url=https://plgegklqtdjxeglvyjte.supabase.co; ref=origin/main; slug=rjbookstop;
else url=https://puoaiyezsreowpwxzxhj.supabase.co; ref=origin/staging; slug=raysandjudys; fi
k=$(git show "$ref:config.js" | grep -oE "(sb_publishable_[A-Za-z0-9_-]+|eyJ[A-Za-z0-9._-]+)" | head -1)
fail=0
for t in app_settings catalog preorders tenants user_profiles order_submissions settings subscriptions usage_events weekly_shipment reservation_history; do
  c=$(curl.exe -s -o /dev/null -w "%{http_code}" "$url/rest/v1/$t?select=*&limit=1" -H "apikey: $k")
  [ "$c" = 401 ] && r=ok || { r=FAIL; fail=1; }; printf "table %-20s %s %s\n" "$t" "$c" "$r"
done
rpc(){ c=$(curl.exe -s -o /tmp/gj -w "%{http_code}" -X POST "$url/rest/v1/rpc/$1" -H "apikey: $k" -H "Content-Type: application/json" -d "$2")
  [ "$c" = 200 ] && r=ok || { r=FAIL; fail=1; }; printf "rpc   %-24s %s %s  %s\n" "$1" "$c" "$r" "$(head -c 70 /tmp/gj)"; }
rpc resolve_tenant_by_slug "{\"p_slug\":\"$slug\"}"
tid=$(sed -E 's/.*"id":"([^"]+)".*/\1/' /tmp/gj)
rpc is_maintenance_mode "{\"p_tenant_id\":\"$tid\"}"
monday=$(date -d "last monday" +%F 2>/dev/null || date +%F)
rpc get_pull_feed_week "{\"p_slug\":\"$slug\",\"p_week_start\":\"$monday\"}"
rpc get_pull_feed_spotlight "{\"p_slug\":\"$slug\",\"p_week_start\":\"$monday\"}"
echo; [ $fail = 0 ] && echo "G-J PROBE: PASS ($env)" || echo "G-J PROBE: FAIL ($env)"
