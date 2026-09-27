#!/usr/bin/env bash
# 用專用測試帳號從 prod 錄一份真實回應，存成 MyMoneyAPITests 的 fixture。
# 流程與注意事項見 tests/MyMoneyAPITests/Fixtures/README.md。
#
# 用法:
#   scripts/record-fixture.sh <fixture 檔名> <METHOD> <path> [JSON body] [--no-auth | --bad-token]
#
#   body 裡的 __EMAIL__、__PASSWORD__ 會換成測試帳號的 email 與密碼，
#   所以密碼不會出現在指令列、shell history 或 repo 裡。
#   預設會先登入測試帳號，再帶 Authorization: Bearer 呼叫;
#   --no-auth 不帶 token(用於 /auth/*),--bad-token 帶一個無效的 token(用於錄 401)。
#
# 例:
#   scripts/record-fixture.sh auth-login-success.json POST /auth/login \
#     '{"email":"__EMAIL__","password":"__PASSWORD__"}' --no-auth
set -euo pipefail

readonly BASE_URL="https://my-money-api.onion523.workers.dev"
readonly TEST_EMAIL="mymoney-ios-test@example.com"
readonly KEYCHAIN_SERVICE="my-money-ios-test"
readonly FAKE_JWT="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.ZmFrZS1maXh0dXJlLXRva2Vu.ZmFrZS1zaWduYXR1cmU"

if [[ $# -lt 3 ]]; then
  sed -n '2,16p' "$0"
  exit 64
fi

name="$1"
method="$2"
path="$3"
body="${4:-}"
mode="${5:-auth}"
if [[ "$body" == --* ]]; then
  mode="$body"
  body=""
fi

fixtures_dir="$(cd "$(dirname "$0")/.." && pwd)/tests/MyMoneyAPITests/Fixtures"
output="$fixtures_dir/$name"
# 先確定寫得進去再打 API:有些請求(例如註冊)只能成功一次，回應寫檔失敗就再也錄不到。
mkdir -p "$fixtures_dir"
touch "$output.raw"

# 密碼優先讀環境變數，否則讀本機 Keychain;兩者都不會印出來。
password="${MYMONEY_TEST_PASSWORD:-}"
if [[ -z "$password" ]]; then
  password="$(security find-generic-password -s "$KEYCHAIN_SERVICE" -a "$TEST_EMAIL" -w)"
fi

json_escape() {
  python3 -c 'import json,sys; print(json.dumps(sys.argv[1])[1:-1])' "$1"
}

fill_placeholders() {
  local text="$1"
  text="${text//__EMAIL__/$(json_escape "$TEST_EMAIL")}"
  text="${text//__PASSWORD__/$(json_escape "$password")}"
  printf '%s' "$text"
}

token=""
case "$mode" in
  --no-auth) ;;
  --bad-token) token="invalid-token-for-fixture" ;;
  auth)
    login_body="$(fill_placeholders '{"email":"__EMAIL__","password":"__PASSWORD__"}')"
    token="$(curl -sS -X POST "$BASE_URL/auth/login" \
      -H 'Content-Type: application/json' --data-binary @- <<<"$login_body" \
      | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["token"])')"
    ;;
  *) echo "未知的選項:$mode" >&2; exit 64 ;;
esac

curl_args=(-sS -X "$method" "$BASE_URL$path" -H 'Content-Type: application/json'
  -o "$output.raw" -w '%{http_code} %{content_type}\n')
if [[ -n "$token" ]]; then
  curl_args+=(-H "Authorization: Bearer $token")
fi
if [[ -n "$body" ]]; then
  status_line="$(fill_placeholders "$body" | curl "${curl_args[@]}" --data-binary @-)"
else
  status_line="$(curl "${curl_args[@]}")"
fi

# 把回應裡的 JWT 換成假值，避免真的 token 進 repo。
sed -E "s/eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/$FAKE_JWT/g" "$output.raw" > "$output"
rm -f "$output.raw"

if grep -qF -- "$password" "$output"; then
  rm -f "$output"
  echo "回應裡出現了測試帳號的密碼，已刪除 fixture,請改用別的 endpoint 錄製。" >&2
  exit 1
fi

echo "$name ← $method $path → HTTP $status_line"
