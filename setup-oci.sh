#!/usr/bin/env bash
# Sets up the Sales Dashboard on an Oracle Linux 9 server (OCI).
# Usage (on the server, after copying index.html to /home/opc):
#   sudo bash setup-oci.sh                # uses /home/opc/index.html
#   sudo bash setup-oci.sh /path/to/index.html
# Safe to run again: use it to publish an updated index.html.
set -euo pipefail

SRC="${1:-/home/opc/index.html}"
WEBROOT="/usr/share/nginx/html"

if [[ $EUID -ne 0 ]]; then
  echo "Please run with sudo:  sudo bash $0 $*"; exit 1
fi
if [[ ! -f "$SRC" ]]; then
  echo "Can't find $SRC. Copy index.html to the server first (see the instructions)."; exit 1
fi

echo "==> Installing nginx (if needed)"
dnf -y install nginx >/dev/null

echo "==> Publishing the dashboard"
install -m 644 -o root -g root "$SRC" "$WEBROOT/index.html"
# SELinux: give the file the label nginx is allowed to read (avoids '403 Forbidden')
restorecon -R "$WEBROOT" || true

echo "==> Web server settings"
cat > /etc/nginx/conf.d/sales-dashboard.conf <<'EOF'
# Sales Dashboard: small hardening and caching tweaks
server_tokens off;
add_header X-Content-Type-Options nosniff always;
add_header X-Frame-Options SAMEORIGIN always;
add_header Referrer-Policy no-referrer always;
gzip on;
gzip_types text/html text/css application/javascript;
EOF
nginx -t
systemctl enable nginx >/dev/null 2>&1
systemctl restart nginx

echo "==> Opening port 80 in the server firewall"
if systemctl is-active --quiet firewalld; then
  firewall-cmd --permanent --add-service=http >/dev/null
  firewall-cmd --reload >/dev/null
else
  echo "    firewalld is not running; skipping"
fi

echo "==> Checking"
code=$(curl -s -o /dev/null -w '%{http_code}' http://localhost/)
if [[ "$code" == "200" ]] && curl -s http://localhost/ | grep -q "Sales Dashboard"; then
  ip=$(curl -s --max-time 3 http://169.254.169.254/opc/v2/vnics/ -H "Authorization: Bearer Oracle" \
        | grep -o '"publicIp" *: *"[^"]*"' | head -1 | grep -o '[0-9.]\{7,\}' || true)
  echo
  echo "Done. The dashboard is running on this server."
  echo "Share this link:  http://${ip:-<your-instance-public-IP>}/"
  echo "(If the link doesn't open from outside, add the port 80 ingress rule in the OCI console.)"
else
  echo "Something went wrong: the server answered HTTP $code. Check: sudo journalctl -u nginx"; exit 1
fi
