#!/usr/bin/env bash
# Sets up the Wax install server on a fresh Ubuntu VPS (Oracle Always Free works).
#
#   sudo ./install.sh <domain>            install
#   ./install.sh --dry-run <domain>       print every step, change nothing
#
# <domain> must already point at this machine (an A record, or a name like 1-2-3-4.sslip.io).
# It installs Caddy (HTTPS) and the upload service, makes a random token, opens only ports 22, 80 and 443,
# turns on fail2ban, and prints the one line to paste into Wax.
set -euo pipefail

DRY=0
if [ "${1:-}" = "--dry-run" ]; then DRY=1; shift; fi
DOMAIN="${1:-}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() { echo "error: $*" >&2; exit 1; }
[[ "$DOMAIN" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]] || die "usage: install.sh [--dry-run] <domain>   (for example install.sh wax.example.com)"
[ "$DRY" = 1 ] || [ "$(id -u)" = 0 ] || die "run with sudo (or use --dry-run to preview)"

run() { if [ "$DRY" = 1 ]; then echo "+ $*"; else "$@"; fi; }

# Writes stdin to a file with the given mode. Contents are never echoed, so a token cannot leak into the log.
put() {
  local mode="$1" path="$2"
  if [ "$DRY" = 1 ]; then echo "+ write $path (mode $mode)"; cat >/dev/null
  else ( umask 077; cat >"$path" ); chmod "$mode" "$path"; fi
}

if [ "$DRY" = 1 ]; then TOKEN="<random 40-character token>"; else TOKEN="$(openssl rand -hex 20)"; fi

echo "== packages"
run apt-get update
run apt-get install -y debian-keyring debian-archive-keyring apt-transport-https curl gpg python3 ufw fail2ban openssl
if [ "$DRY" = 1 ] || ! command -v caddy >/dev/null; then
  run bash -c "curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg"
  # Verify the pinned GPG key fingerprint (Caddy primary key: 6576 0C51 EDEA 2017 CEA2 CA15 155B 6D79 CA56 EA34)
  if [ "$DRY" = 0 ]; then
    if ! gpg --show-keys /usr/share/keyrings/caddy-stable-archive-keyring.gpg 2>/dev/null | grep -q "155B 6D79 CA56 EA34"; then
      die "Caddy GPG key fingerprint mismatch. Key may have rotated; update install.sh."
    fi
  fi
  run bash -c "curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' -o /etc/apt/sources.list.d/caddy-stable.list"
  run apt-get update
  run apt-get install -y caddy
fi

echo "== upload service"
run useradd --system --home /opt/wax-ota --shell /usr/sbin/nologin wax-ota || true
run install -d -o root -g root -m 755 /opt/wax-ota
run install -m 644 "$HERE/wax_ota.py" /opt/wax-ota/wax_ota.py
run install -d -o wax-ota -g wax-ota -m 755 /var/www/signed-www/ota
printf 'WAX_OTA_TOKEN=%s\nWAX_OTA_ROOT=/var/www/signed-www/ota\n' "$TOKEN" | put 600 /etc/wax-ota.env
put 644 /etc/systemd/system/wax-ota.service <<'UNIT'
[Unit]
Description=Wax OTA upload endpoint
After=network.target

[Service]
User=wax-ota
EnvironmentFile=/etc/wax-ota.env
ExecStart=/usr/bin/python3 /opt/wax-ota/wax_ota.py
Restart=on-failure
NoNewPrivileges=true
ProtectSystem=strict
ReadWritePaths=/var/www/signed-www/ota
PrivateTmp=true
ProtectHome=true

[Install]
WantedBy=multi-user.target
UNIT

echo "== web server (Caddyfile)"
CADDYFILE="$(sed "s/{{DOMAIN}}/$DOMAIN/g" "$HERE/Caddyfile.example")"
if [ "$DRY" = 1 ]; then echo "$CADDYFILE"; fi
printf '%s\n' "$CADDYFILE" | put 644 /etc/caddy/Caddyfile

echo "== firewall and brute-force protection"
run ufw default deny incoming
run ufw default allow outgoing
run ufw allow 22/tcp
run ufw allow 80/tcp
run ufw allow 443/tcp
run ufw --force enable
run systemctl enable --now fail2ban

echo "== start"
run systemctl daemon-reload
run systemctl enable --now wax-ota
run systemctl restart caddy

echo
echo "Done. Paste this line into Wax (Settings, Install host, Paste):"
echo
echo "WAXINSTALL1 https://$DOMAIN $TOKEN"
echo
echo "The token is stored only in /etc/wax-ota.env (readable by root). Keep this line private."
