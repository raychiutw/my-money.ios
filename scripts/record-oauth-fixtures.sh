#!/usr/bin/env bash
# 用專用測試帳號走一次 OAuth 授權碼流程(#334),錄下 /oauth/token 與 /oauth/revoke 的真實回應。
# 流程與注意事項見 tests/MyMoneyAPITests/Fixtures/README.md「OAuth(#334)」。
#
# 用法:scripts/record-oauth-fixtures.sh
#
# 1. GET /oauth/authorize(client_id=ios、PKCE S256),從 Worker 的登入頁取出 csrf_token
# 2. POST /oauth/authorize(form:csrf_token、mode=login、email、password)→ 302 到 callback,取出 code
# 3. POST /oauth/token(grant_type=authorization_code)→ oauth-token-authorization-code.json
# 4. 同一個 code 再換一次 → oauth-token-invalid-grant.json(400,授權碼已被使用)
# 5. POST /oauth/token(grant_type=refresh_token)→ oauth-token-refresh.json(輪替後的新更新權杖,#335)
# 6. 用不存在的更新權杖 refresh → oauth-token-refresh-invalid-grant.json(400)
# 7. POST /oauth/revoke 撤銷剛建立的工作階段 → oauth-revoke.json(測試帳號不留下多餘的登入裝置)
#
# 存檔前:存取權杖(JWT)只換掉簽章,header 與 payload(sub、email、name)保留給測試解出使用者;
# 更新權杖換成假值。密碼只從環境變數或 Keychain 讀進 python,不會出現在指令列或輸出。
set -euo pipefail

readonly TEST_EMAIL="mymoney-ios-test@example.com"
readonly KEYCHAIN_SERVICE="my-money-ios-test"

fixtures_dir="$(cd "$(dirname "$0")/.." && pwd)/tests/MyMoneyAPITests/Fixtures"
mkdir -p "$fixtures_dir"

if [[ -z "${MYMONEY_TEST_PASSWORD:-}" ]]; then
  MYMONEY_TEST_PASSWORD="$(security find-generic-password -s "$KEYCHAIN_SERVICE" -a "$TEST_EMAIL" -w)"
fi
export MYMONEY_TEST_PASSWORD TEST_EMAIL

python3 -I - "$fixtures_dir" <<'PY'
import base64, hashlib, json, os, re, secrets, sys, urllib.error, urllib.parse, urllib.request

BASE = "https://my-money-api.onion523.workers.dev"
REDIRECT = "com.raychiu.mymoney:/oauth/callback"
UA = "MyMoney-iOS (iPhone) fixture-recorder"
FAKE_SIGNATURE = "ZmFrZS1zaWduYXR1cmU"
FAKE_REFRESH = "fake-fixture-refresh-token"
FAKE_ROTATED = "fake-fixture-rotated-refresh-token"
out_dir = sys.argv[1]
password = os.environ["MYMONEY_TEST_PASSWORD"]

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None

opener = urllib.request.build_opener(NoRedirect)

def call(method, path, form=None):
    data = urllib.parse.urlencode(form).encode() if form is not None else None
    request = urllib.request.Request(BASE + path, data=data, method=method, headers={"User-Agent": UA})
    if data is not None:
        request.add_header("Content-Type", "application/x-www-form-urlencoded")
    try:
        with opener.open(request) as response:
            return response.status, response.headers, response.read()
    except urllib.error.HTTPError as error:
        return error.code, error.headers, error.read()

def b64url(raw):
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()

verifier = b64url(secrets.token_bytes(32))
challenge = b64url(hashlib.sha256(verifier.encode()).digest())
state = b64url(secrets.token_bytes(16))

query = urllib.parse.urlencode({
    "client_id": "ios", "redirect_uri": REDIRECT, "response_type": "code",
    "code_challenge": challenge, "code_challenge_method": "S256", "state": state, "scope": "full",
})
status, _, body = call("GET", "/oauth/authorize?" + query)
match = re.search(rb'name="csrf_token" value="([^"]+)"', body)
if status != 200 or not match:
    sys.exit(f"登入頁沒有 csrf_token(HTTP {status})")

status, headers, _ = call("POST", "/oauth/authorize", {
    "csrf_token": match.group(1).decode(), "mode": "login",
    "email": os.environ["TEST_EMAIL"], "password": password,
})
callback = urllib.parse.urlparse(headers.get("Location") or "")
params = urllib.parse.parse_qs(callback.query)
if status != 302 or params.get("state") != [state] or "code" not in params:
    sys.exit(f"登入沒有導回 callback(HTTP {status})")
code = params["code"][0]

exchange = {"grant_type": "authorization_code", "code": code, "redirect_uri": REDIRECT,
            "client_id": "ios", "code_verifier": verifier}

real_refreshes = {}  # 真的更新權杖 → 假值

def sanitize(raw):
    text = raw.decode()
    text = re.sub(r"(eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.)[A-Za-z0-9_-]+", r"\1" + FAKE_SIGNATURE, text)
    for real, fake in real_refreshes.items():
        text = text.replace(real, fake)
    if password in text or any(real in text for real in real_refreshes):
        sys.exit("回應裡還有密碼或真的更新權杖,不存檔")
    return text

def save(name, status, text):
    with open(os.path.join(out_dir, name), "w") as file:
        file.write(text)
    print(f"{name} → HTTP {status}")

status, _, body = call("POST", "/oauth/token", exchange)
if status != 200:
    sys.exit(f"換碼失敗(HTTP {status})")
refresh = json.loads(body)["refresh_token"]
real_refreshes[refresh] = FAKE_REFRESH
save("oauth-token-authorization-code.json", status, sanitize(body))

status, _, body = call("POST", "/oauth/token", exchange)
save("oauth-token-invalid-grant.json", status, sanitize(body))

status, _, body = call("POST", "/oauth/token", {"grant_type": "refresh_token", "refresh_token": refresh, "client_id": "ios"})
if status == 200:
    rotated = json.loads(body)["refresh_token"]
    real_refreshes[rotated] = FAKE_ROTATED
    save("oauth-token-refresh.json", status, sanitize(body))
    refresh = rotated
else:
    print(f"refresh 失敗(HTTP {status}),不存 oauth-token-refresh.json")

status, _, body = call("POST", "/oauth/token", {
    "grant_type": "refresh_token", "refresh_token": b64url(secrets.token_bytes(32)), "client_id": "ios",
})
save("oauth-token-refresh-invalid-grant.json", status, sanitize(body))

status, _, body = call("POST", "/oauth/revoke", {"token": refresh})
save("oauth-revoke.json", status, sanitize(body))
PY
