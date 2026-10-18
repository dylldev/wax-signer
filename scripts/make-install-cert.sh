#!/usr/bin/env bash
# Issues a Let's Encrypt certificate for the install name (which points at 127.0.0.1) and writes cert.json for Wax.
#   DuckDNS_Token=... scripts/make-install-cert.sh <domain> <output-dir>
# cert.json: {"name", "notAfter" (ISO 8601), "p12" (base64 PKCS#12: chain + key), "password"}.
# The key is public by design: the name only ever resolves to the phone it is opened on. A new key is made each run.
# ACME_SH may name another acme.sh (tests use a fake).
set -euo pipefail
DOMAIN="${1:-}"; OUT="${2:-}"
[[ "$DOMAIN" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]] || { echo "usage: make-install-cert.sh <domain> <output-dir>" >&2; exit 1; }
[ -n "$OUT" ] || { echo "usage: make-install-cert.sh <domain> <output-dir>" >&2; exit 1; }
ACME="${ACME_SH:-acme.sh}"
HOME_DIR="$(mktemp -d)"; trap 'rm -rf "$HOME_DIR"' EXIT
mkdir -p "$OUT"

"$ACME" --home "$HOME_DIR" --issue --dns dns_duckdns -d "$DOMAIN" --keylength 2048 --server letsencrypt --force >&2
KEY="$HOME_DIR/$DOMAIN/$DOMAIN.key"; CHAIN="$HOME_DIR/$DOMAIN/fullchain.cer"
[ -s "$KEY" ] && [ -s "$CHAIN" ] || { echo "error: acme.sh did not produce a key and chain" >&2; exit 1; }

PASSWORD="wax"
openssl pkcs12 -export -inkey "$KEY" -in "$CHAIN" -passout "pass:$PASSWORD" -out "$HOME_DIR/bundle.p12"
END="$(openssl x509 -in "$CHAIN" -noout -enddate | sed 's/notAfter=//')"
NOT_AFTER="$(python3 - "$END" <<'PY'
import sys, datetime
print(datetime.datetime.strptime(sys.argv[1].replace("  ", " "), "%b %d %H:%M:%S %Y %Z").strftime("%Y-%m-%dT%H:%M:%SZ"))
PY
)"
python3 - "$DOMAIN" "$NOT_AFTER" "$HOME_DIR/bundle.p12" "$PASSWORD" "$OUT/cert.json" <<'PY'
import sys, json, base64
name, not_after, p12, password, out = sys.argv[1:]
json.dump({"name": name, "notAfter": not_after, "p12": base64.b64encode(open(p12, "rb").read()).decode(), "password": password}, open(out, "w"))
PY
echo "wrote $OUT/cert.json (expires $NOT_AFTER)" >&2
