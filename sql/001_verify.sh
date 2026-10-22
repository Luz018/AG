#!/bin/bash
# 001_verify.sh - forged-insert tests, run AFTER 001_security_fixes.sql.
# Acts exactly like a stranger on the internet: uses only the public (anon)
# key from config.js. Run from the project folder:   bash sql/001_verify.sh
#
# Tests 1-9 must each be REFUSED (HTTP 401/403 + "row-level security" error).
# Test 10 must be ACCEPTED (HTTP 201) and creates ONE test row (first name
# ZZTEST) that an admin then deletes in the SQL editor. Nothing else is written.

cd "$(dirname "$0")/.." || exit 1
U=https://lgqprlewydtpfrmdhotm.supabase.co
K=$(grep -o "eyJ[A-Za-z0-9._-]*" config.js)
FUT=$(date -d "+14 days" +%F 2>/dev/null || date -v+14d +%F)

# a valid body; each test overrides ONE field by appending JSON (last key wins)
base() {
  cat <<JSON
{"first_name":"ZZTEST","last_name":"Check","phone":"670000000","email":"zztest@example.com","visitor_type":"individual","target_official":"gov","purpose":"verification test","preferred_date":"$FUT"$1}
JSON
}

run() {  # name, extra-json, expected-status-prefix, [Prefer header]
  local out code r
  out=$(curl -sS -m 20 -w "\n%{http_code}" -X POST "$U/rest/v1/requests" \
        -H "apikey: $K" -H "Authorization: Bearer $K" -H "Content-Type: application/json" \
        -H "Prefer: ${4:-return=minimal}" -d "$(base "$2")")
  code=$(echo "$out" | tail -1)
  if [[ "$code" == $3* ]]; then r=PASS; else r=FAIL; fi
  printf "%-4s %-44s HTTP %s  %s\n" "$r" "$1" "$code" "$(echo "$out" | head -n -1 | cut -c1-110)"
}

echo "--- must be REFUSED (4xx) ---"
run "1  status = approved"               ',"status":"approved"'                     4
run "2  status = declined"               ',"status":"declined"'                     4
run "3  status = delegated"              ',"status":"delegated"'                    4
run "4  reject_reason pre-filled"        ',"reject_reason":"x"'                     4
run "5  delegate_to pre-filled"          ',"delegate_to":"sg"'                      4
run "6  flagged_for_reschedule = true"   ',"flagged_for_reschedule":true'           4
run "7  backdated created_at"            ',"created_at":"2020-01-01T00:00:00Z"'     4
run "8  unknown office"                  ',"target_official":"president"'           4
run "9a email missing (null)"            ',"email":null'                            4
run "9b email malformed"                 ',"email":"not-an-email"'                  4

echo "--- must be ACCEPTED (201); returned reference must start AG-, not FAKE-1 ---"
run "10 valid request, fake reference sent" ',"reference_number":"FAKE-1"' 201 "return=representation"
