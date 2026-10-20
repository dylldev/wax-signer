#!/usr/bin/env bash
# Issues a Let's Encrypt certificate for the install name (which points at 127.0.0.1) and writes cert.json for Wax.
#   DuckDNS_Token=... scripts/make-install-cert.sh <domain> <output-dir>
# cert.json: {"name", "notAfter" (ISO 8601), "p12" (base64 PKCS#12: chain + key), "password"}.
# The key is public by design: the name only ever resolves to the phone it is opened on. A new key is made each run.
# ACME_SH may name another acme.sh (tests use a fake). ACME_HOME is where the ACME account is kept between runs.
set -euo pipefail
DOMAIN="${1:-}"; OUT="${2:-}"
[[ "$DOMAIN" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]] || { echo "usage: make-install-cert.sh <domain> <output-dir>" >&2; exit 1; }
[ -n "$OUT" ] || { echo "usage: make-install-cert.sh <domain> <output-dir>" >&2; exit 1; }
ACME="${ACME_SH:-acme.sh}"
# The account registration lives in ACME_HOME and must survive between runs: Let's Encrypt caps how many
# accounts one IP may create, and shared CI runners share an IP. The domain's key and certificate do not --
# they are deleted before every run so a new key is made each time, as advertised above.
ACME_HOME="${ACME_HOME:-$HOME/.acme.sh}"
case "$ACME_HOME" in ""|"/") echo "error: ACME_HOME must be a directory" >&2; exit 1;; esac
mkdir -p "$ACME_HOME"
rm -rf "${ACME_HOME:?}/$DOMAIN"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
mkdir -p "$OUT"

"$ACME" --home "$ACME_HOME" --issue --dns dns_duckdns -d "$DOMAIN" --keylength 2048 --server letsencrypt --force >&2
KEY="$ACME_HOME/$DOMAIN/$DOMAIN.key"; CHAIN="$ACME_HOME/$DOMAIN/fullchain.cer"
[ -s "$KEY" ] && [ -s "$CHAIN" ] || { echo "error: acme.sh did not produce a key and chain" >&2; exit 1; }

PASSWORD="wax"
openssl pkcs12 -export -inkey "$KEY" -in "$CHAIN" -passout "pass:$PASSWORD" -out "$WORK/bundle.p12"
END="$(openssl x509 -in "$CHAIN" -noout -enddate | sed 's/notAfter=//')"
NOT_AFTER="$(python3 - "$END" <<'PY'
import sys, datetime
print(datetime.datetime.strptime(sys.argv[1].replace("  ", " "), "%b %d %H:%M:%S %Y %Z").strftime("%Y-%m-%dT%H:%M:%SZ"))
PY
)"
python3 - "$DOMAIN" "$NOT_AFTER" "$WORK/bundle.p12" "$PASSWORD" "$OUT/cert.json" <<'PY'
import sys, json, base64
name, not_after, p12, password, out = sys.argv[1:]
json.dump({"name": name, "notAfter": not_after, "p12": base64.b64encode(open(p12, "rb").read()).decode(), "password": password}, open(out, "w"))
PY
echo "wrote $OUT/cert.json (expires $NOT_AFTER)" >&2
