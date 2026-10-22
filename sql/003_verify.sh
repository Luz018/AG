#!/bin/bash
# 003_verify.sh - run AFTER 003_submit_request.sql. Uses only the public (anon) key.
#   bash sql/003_verify.sh
#
# Part A: the original ten DIRECT-insert tests. After 003, ALL TEN must be
#         refused (4xx) - including the valid one (test 10), because the public
#         can no longer insert into the table directly.
# Part B: the function. Valid calls must return an AG-... reference; each bad
#         call must be refused. Calls that SUCCEED create one ZZTEST row each.

cd "$(dirname "$0")/.." || exit 1
U=https://lgqprlewydtpfrmdhotm.supabase.co
K=$(grep -o "eyJ[A-Za-z0-9._-]*" config.js)
FUT=$(date -d "+14 days" +%F 2>/dev/null || date -v+14d +%F)

base() {
  cat <<JSON
{"first_name":"ZZTEST","last_name":"Check","phone":"670000000","email":"zztest@example.com","visitor_type":"individual","target_official":"gov","purpose":"verification test","preferred_date":"$FUT"$1}
JSON
}
direct() {  # name, extra-json
  local out code r
  out=$(curl -sS -m 20 -w "\n%{http_code}" -X POST "$U/rest/v1/requests" \
        -H "apikey: $K" -H "Authorization: Bearer $K" -H "Content-Type: application/json" \
        -H "Prefer: return=minimal" -d "$(base "$2")")
  code=$(echo "$out" | tail -1)
  if [[ "$code" == 4* ]]; then r=PASS; else r=FAIL; fi
  printf "%-4s %-44s HTTP %s  %s\n" "$r" "$1" "$code" "$(echo "$out" | head -n -1 | cut -c1-90)"
}

echo "=== Part A: direct inserts into the table - ALL must be refused ==="
direct "1  status = approved"             ',"status":"approved"'
direct "2  status = declined"             ',"status":"declined"'
direct "3  status = delegated"            ',"status":"delegated"'
direct "4  reject_reason pre-filled"      ',"reject_reason":"x"'
direct "5  delegate_to pre-filled"        ',"delegate_to":"sg"'
direct "6  flagged_for_reschedule = true" ',"flagged_for_reschedule":true'
direct "7  backdated created_at"          ',"created_at":"2020-01-01T00:00:00Z"'
direct "8  unknown office"                ',"target_official":"president"'
direct "9a email missing (null)"          ',"email":null'
direct "9b email malformed"               ',"email":"not-an-email"'
direct "10 fully VALID direct insert"     ',"reference_number":"FAKE-1"'

fn() {  # name, expected-prefix, json-body
  local out code r
  out=$(curl -sS -m 20 -w "\n%{http_code}" -X POST "$U/rest/v1/rpc/submit_request" \
        -H "apikey: $K" -H "Authorization: Bearer $K" -H "Content-Type: application/json" -d "$3")
  code=$(echo "$out" | tail -1)
  if [[ "$code" == $2* ]]; then r=PASS; else r=FAIL; fi
  printf "%-4s %-44s HTTP %s  %s\n" "$r" "$1" "$code" "$(echo "$out" | head -n -1 | cut -c1-90)"
}
good() {
  echo "{\"p_first_name\":\"ZZTEST\",\"p_last_name\":\"Fn\",\"p_phone\":\"670000000\",\"p_email\":\"zztest@example.com\",\"p_visitor_type\":\"individual\",\"p_visitor_detail\":null,\"p_target_official\":\"gov\",\"p_purpose\":\"verification test\",\"p_preferred_date\":\"$FUT\"$1}"
}

echo "=== Part B: submit_request ==="
fn "B1 valid call (must return AG-...)"      2 "$(good '')"
fn "B2 email missing"                        4 "$(good ',"p_email":null')"
fn "B3 email malformed"                      4 "$(good ',"p_email":"nope"')"
fn "B4 unknown office"                       4 "$(good ',"p_target_official":"president"')"
fn "B5 phone too short"                      4 "$(good ',"p_phone":"123"')"
fn "B6 date in the past"                     4 "$(good ',"p_preferred_date":"2020-01-01"')"
fn "B7 purpose over 50 words"                4 "$(good ',"p_purpose":"'"$(printf 'word %.0s' $(seq 1 60))"'"')"
fn "B8 try to sneak in status=approved"      4 "$(good ',"p_status":"approved"')"
fn "B9 try to sneak in reference number"     4 "$(good ',"p_reference_number":"FAKE-1"')"
