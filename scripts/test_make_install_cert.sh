#!/usr/bin/env bash
# Run: bash scripts/test_make_install_cert.sh  (uses a fake acme.sh; no network, no DuckDNS)
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fail=0
check() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1 (wanted $2, got $3)"; fail=1; fi; }
T="$(mktemp -d)"
cat > "$T/fake-acme.sh" <<'FAKE'
#!/usr/bin/env bash
# args: --home DIR --issue --dns ... -d DOMAIN ...
while [ $# -gt 0 ]; do case "$1" in --home) H="$2"; shift;; -d) D="$2"; shift;; esac; shift; done
mkdir -p "$H/$D"
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$H/$D/$D.key" -out "$H/$D/fullchain.cer" -days 90 -subj "/CN=$D" 2>/dev/null
FAKE
chmod +x "$T/fake-acme.sh"

ACME_SH="$T/fake-acme.sh" bash "$HERE/make-install-cert.sh" wax.example.test "$T/out" >/dev/null 2>&1; check "script succeeds" 0 $?
check "name" "wax.example.test" "$(python3 -c "import json;print(json.load(open('$T/out/cert.json'))['name'])")"
python3 - "$T/out/cert.json" <<'PY'
import json, sys, base64, datetime
j = json.load(open(sys.argv[1]))
assert j["password"] == "wax"
assert len(base64.b64decode(j["p12"])) > 500
d = datetime.datetime.strptime(j["notAfter"], "%Y-%m-%dT%H:%M:%SZ")
assert 85 <= (d - datetime.datetime.utcnow()).days <= 91, d
PY
check "p12 and expiry are valid" 0 $?
base64 -d < <(python3 -c "import json;print(json.load(open('$T/out/cert.json'))['p12'])") > "$T/b.p12"
openssl pkcs12 -in "$T/b.p12" -passin pass:wax -nokeys -noout 2>/dev/null; check "p12 opens with the password" 0 $?
ACME_SH="$T/fake-acme.sh" bash "$HERE/make-install-cert.sh" "bad domain;x" "$T/out2" >/dev/null 2>&1; check "bad domain refused" 1 $?
ACME_SH=/bin/false bash "$HERE/make-install-cert.sh" wax.example.test "$T/out3" >/dev/null 2>&1; check "issue failure fails the script" 1 $?
exit $fail
