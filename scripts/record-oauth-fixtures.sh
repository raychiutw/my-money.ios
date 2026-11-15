#!/usr/bin/env bash
# 用專用測試帳號走一次 OAuth 授權碼流程(#334),錄下 /oauth/token 與 /oauth/revoke 的真實回應。
# 流程與注意事項見 tests/MyMoneyAPITests/Fixtures/README.md「OAuth(#334)」。
#
# 用法:scripts/record-oauth-fixtures.sh [account-security | passkey]
#
# 1. GET /oauth/authorize(client_id=ios、PKCE S256),從 Worker 的登入頁取出 csrf_token
# 2. POST /oauth/authorize(form:csrf_token、mode=login、email、password)→ 302 到 callback,取出 code
# 3. POST /oauth/token(grant_type=authorization_code)→ oauth-token-authorization-code.json
# 4. 同一個 code 再換一次 → oauth-token-invalid-grant.json(400,授權碼已被使用)
# 5. POST /oauth/token(grant_type=refresh_token)→ oauth-token-refresh.json(輪替後的新更新權杖,#335)
# 6. 用不存在的更新權杖 refresh → oauth-token-refresh-invalid-grant.json(400)
# 7. POST /oauth/revoke 撤銷剛建立的工作階段 → oauth-revoke.json(測試帳號不留下多餘的登入裝置)
#
# 加上 account-security 時改錄「帳號安全」(#338)的 /auth/sessions 與 /auth/password,
# 見 README「帳號安全(#338)」;錄完撤銷建立的兩個工作階段。
# 加上 passkey 時改錄 passkey(#339)的 options、清單與錯誤回應,見 README「Passkey(#339)」;不建立任何 passkey。
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

python3 -I - "$fixtures_dir" "${1:-oauth}" <<'PY'
import base64, hashlib, json, os, re, secrets, sys, urllib.error, urllib.parse, urllib.request

BASE = "https://my-money-api.onion523.workers.dev"
REDIRECT = "com.raychiu.mymoney:/oauth/callback"
UA = "MyMoney-iOS (iPhone) fixture-recorder"
IPAD_UA = "MyMoney-iOS (iPad) fixture-recorder"
FAKE_SIGNATURE = "ZmFrZS1zaWduYXR1cmU"
FAKE_REFRESH = "fake-fixture-refresh-token"
FAKE_ROTATED = "fake-fixture-rotated-refresh-token"
out_dir = sys.argv[1]
mode = sys.argv[2]
password = os.environ["MYMONEY_TEST_PASSWORD"]

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None

opener = urllib.request.build_opener(NoRedirect)

def call(method, path, form=None, json_body=None, token=None, ua=UA):
    data = None
    request = urllib.request.Request(BASE + path, method=method, headers={"User-Agent": ua})
    if form is not None:
        data = urllib.parse.urlencode(form).encode()
        request.add_header("Content-Type", "application/x-www-form-urlencoded")
    if json_body is not None:
        data = json.dumps(json_body).encode()
        request.add_header("Content-Type", "application/json")
    if token:
        request.add_header("Authorization", "Bearer " + token)
    request.data = data
    try:
        with opener.open(request) as response:
            return response.status, response.headers, response.read()
    except urllib.error.HTTPError as error:
        return error.code, error.headers, error.read()

def b64url(raw):
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()

def authorize(ua=UA):
    """走一次授權碼流程,回傳換權杖用的 form。"""
    verifier = b64url(secrets.token_bytes(32))
    challenge = b64url(hashlib.sha256(verifier.encode()).digest())
    state = b64url(secrets.token_bytes(16))
    query = urllib.parse.urlencode({
        "client_id": "ios", "redirect_uri": REDIRECT, "response_type": "code",
        "code_challenge": challenge, "code_challenge_method": "S256", "state": state, "scope": "full",
    })
    status, _, body = call("GET", "/oauth/authorize?" + query, ua=ua)
    match = re.search(rb'name="csrf_token" value="([^"]+)"', body)
    if status != 200 or not match:
        sys.exit(f"登入頁沒有 csrf_token(HTTP {status})")
    status, headers, _ = call("POST", "/oauth/authorize", {
        "csrf_token": match.group(1).decode(), "mode": "login",
        "email": os.environ["TEST_EMAIL"], "password": password,
    }, ua=ua)
    callback = urllib.parse.urlparse(headers.get("Location") or "")
    params = urllib.parse.parse_qs(callback.query)
    if status != 302 or params.get("state") != [state] or "code" not in params:
        sys.exit(f"登入沒有導回 callback(HTTP {status})")
    return {"grant_type": "authorization_code", "code": params["code"][0], "redirect_uri": REDIRECT,
            "client_id": "ios", "code_verifier": verifier}

real_refreshes = {}  # 真的更新權杖 → 假值
# 帳號安全模式的存取權杖:回應裡出現任何一支就不存檔。
real_tokens = []

def sanitize(raw):
    text = raw.decode()
    text = re.sub(r"(eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.)[A-Za-z0-9_-]+", r"\1" + FAKE_SIGNATURE, text)
    for real, fake in real_refreshes.items():
        text = text.replace(real, fake)
    if password in text or any(real in text for real in [*real_refreshes, *real_tokens]):
        sys.exit("回應裡還有密碼或真的權杖,不存檔")
    return text

def save(name, status, text):
    with open(os.path.join(out_dir, name), "w") as file:
        file.write(text)
    print(f"{name} → HTTP {status}")

def sign_in(ua=UA):
    """登入一次,回傳 (存取權杖, 更新權杖, 工作階段 id);權杖不存檔也不印出。"""
    status, _, body = call("POST", "/oauth/token", authorize(ua), ua=ua)
    if status != 200:
        sys.exit(f"換碼失敗(HTTP {status})")
    token = json.loads(body)
    real_tokens.append(token["access_token"])
    real_refreshes[token["refresh_token"]] = FAKE_REFRESH
    payload = token["access_token"].split(".")[1]
    claims = json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4)))
    return token["access_token"], token["refresh_token"], claims["sid"]

if mode == "account-security":
    # 不錄「登出其他所有裝置」與改密碼成功:兩者都會撤銷測試帳號其他所有工作階段(別的 worktree 可能正在用),
    # 改密碼成功還會讓先前核發的舊版權杖失效。這兩份依上游原始碼手寫(README 有註明)。
    access, refresh, _ = sign_in()
    status, headers, body = call("POST", "/auth/password", json_body={
        "current_password": "fixture-wrong-password", "new_password": "fixture-new-password"}, token=access)
    if status != 401 or headers.get("WWW-Authenticate"):
        sys.exit(f"目前密碼錯誤應該是沒有 WWW-Authenticate 的 401(HTTP {status})")
    save("auth-password-wrong-current.json", status, sanitize(body))
    # 新密碼太短在驗證目前密碼之前就擋下,不會改到密碼。
    status, _, body = call("POST", "/auth/password", json_body={
        "current_password": "fixture-wrong-password", "new_password": "12345"}, token=access)
    save("auth-password-too-short.json", status, sanitize(body))
    # 第二台(iPad)登入;登入成功也清掉上面「目前密碼錯誤」累計的失敗次數。
    _, _, other_sid = sign_in(IPAD_UA)
    status, _, body = call("GET", "/auth/sessions", token=access)
    save("auth-sessions.json", status, sanitize(body))
    status, _, body = call("DELETE", "/auth/sessions/" + other_sid, token=access)
    save("auth-session-delete.json", status, sanitize(body))
    status, _, body = call("DELETE", "/auth/sessions/" + other_sid, token=access)
    save("auth-session-delete-not-found.json", status, sanitize(body))
    status, _, _ = call("POST", "/oauth/revoke", {"token": refresh})
    print(f"撤銷錄製用的工作階段 → HTTP {status}")
    sys.exit(0)

if mode == "passkey":
    # 測試帳號沒有 passkey(要真機才建得出來):只錄 options、空清單與錯誤回應,錄完撤銷工作階段。
    access, refresh, _ = sign_in()
    status, _, body = call("POST", "/auth/passkey/login/options", json_body={})
    save("passkey-login-options.json", status, sanitize(body))
    status, _, body = call("POST", "/auth/passkey/register/options", json_body={}, token=access)
    save("passkey-register-options.json", status, sanitize(body))
    status, _, body = call("GET", "/auth/passkeys", token=access)
    save("passkeys-empty.json", status, sanitize(body))
    status, _, body = call("PATCH", "/auth/passkeys/fixture-nonexistent-passkey", json_body={"name": "x"}, token=access)
    save("passkey-rename-not-found.json", status, sanitize(body))
    # 不存在的 challenge:後端在查憑證之前就拒絕,不會留下任何紀錄。
    client_data = b64url(json.dumps({"type": "webauthn.get", "challenge": b64url(secrets.token_bytes(32))}).encode())
    challenge = b64url(hashlib.sha256(b64url(secrets.token_bytes(32)).encode()).digest())
    status, headers, body = call("POST", "/oauth/passkey/authorize", json_body={
        "response": {"id": "fixture", "rawId": "fixture", "type": "public-key",
                     "response": {"clientDataJSON": client_data, "authenticatorData": "", "signature": ""}},
        "client_id": "ios", "redirect_uri": REDIRECT, "code_challenge": challenge,
        "code_challenge_method": "S256", "state": "fixture-state", "scope": "full"})
    if status != 401 or headers.get("WWW-Authenticate"):
        sys.exit(f"passkey 驗證失敗應該是沒有 WWW-Authenticate 的 401(HTTP {status})")
    save("oauth-passkey-authorize-expired.json", status, sanitize(body))
    status, _, _ = call("POST", "/oauth/revoke", {"token": refresh})
    print(f"撤銷錄製用的工作階段 → HTTP {status}")
    sys.exit(0)

exchange = authorize()
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
