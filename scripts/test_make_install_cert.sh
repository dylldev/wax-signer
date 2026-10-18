#!/usr/bin/env bash
# Run: bash scripts/test_make_install_cert.sh  (uses a fake acme.sh; no network, no DuckDNS)
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fail=0
check() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1 (wanted $2, got $3)"; fail=1; fi; }
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
cat > "$T/fake-acme.sh" <<'FAKE'
#!/usr/bin/env bash
# args: --home DIR --issue --dns ... -d DOMAIN ...
while [ $# -gt 0 ]; do case "$1" in --home) H="$2"; shift;; -d) D="$2"; shift;; esac; shift; done
mkdir -p "$H/ca" "$H/$D"
# A real registration happens only once; reusing the home reuses the account.
[ -f "$H/ca/acme-account.json" ] || uuidgen > "$H/ca/acme-account.json"
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$H/$D/$D.key" -out "$H/$D/fullchain.cer" -days 90 -subj "/CN=$D" 2>/dev/null
FAKE
chmod +x "$T/fake-acme.sh"
run() { ACME_HOME="$T/acme-home" ACME_SH="$T/fake-acme.sh" bash "$HERE/make-install-cert.sh" "$@"; }

run wax.example.test "$T/out" >/dev/null 2>&1; check "script succeeds" 0 $?
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

# Let's Encrypt caps new accounts per IP and shared CI runners share an IP, so the account must survive
# between runs -- while the certificate's key is still regenerated every time.
ACCT="$(cat "$T/acme-home/ca/acme-account.json" 2>/dev/null)"
MOD1="$(openssl x509 -in "$T/acme-home/wax.example.test/fullchain.cer" -noout -modulus 2>/dev/null)"
check "the ACME account was registered once" "yes" "$([ -n "$ACCT" ] && echo yes || echo no)"
run wax.example.test "$T/out" >/dev/null 2>&1; check "a second run succeeds" 0 $?
check "the account is reused, not re-registered" "$ACCT" "$(cat "$T/acme-home/ca/acme-account.json" 2>/dev/null)"
MOD2="$(openssl x509 -in "$T/acme-home/wax.example.test/fullchain.cer" -noout -modulus 2>/dev/null)"
check "a new key is still made each run" "different" "$([ "$MOD1" != "$MOD2" ] && [ -n "$MOD2" ] && echo different || echo same)"

ACME_HOME=/ ACME_SH="$T/fake-acme.sh" bash "$HERE/make-install-cert.sh" wax.example.test "$T/out2" >/dev/null 2>&1; check "an ACME_HOME of / is refused" 1 $?
run "bad domain;x" "$T/out2" >/dev/null 2>&1; check "bad domain refused" 1 $?
ACME_HOME="$T/acme-home" ACME_SH=/bin/false bash "$HERE/make-install-cert.sh" wax.example.test "$T/out3" >/dev/null 2>&1; check "issue failure fails the script" 1 $?
exit $fail
