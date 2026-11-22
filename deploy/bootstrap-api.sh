#!/usr/bin/env bash
# Ejecutar en la instancia Oracle como opc: bash bootstrap-api.sh
# Requiere en /tmp: api-bundle.tgz (backend compilado) y backend.env
set -euo pipefail
DOMAIN=api.saberoconsulting.com
EMAIL=robertocarloslopez072@gmail.com

# 1. Swap extra para que dnf/npm no agoten los 512 MB
if ! swapon --show | grep -q /swap2; then
  sudo fallocate -l 2G /swap2 && sudo chmod 600 /swap2 && sudo mkswap /swap2 >/dev/null && sudo swapon /swap2
  grep -q '^/swap2' /etc/fstab || echo '/swap2 none swap sw 0 0' | sudo tee -a /etc/fstab >/dev/null
fi

# 2. Paquetes
command -v node >/dev/null && node -v | grep -q '^v24' || { curl -fsSL https://rpm.nodesource.com/setup_24.x | sudo bash - ; }
sudo dnf install -y nodejs nginx python3-certbot-nginx
sudo firewall-cmd --permanent --add-service=http --add-service=https; sudo firewall-cmd --reload

# 3. Usuario, carpetas, backend
id sabero >/dev/null 2>&1 || sudo useradd -r -m -d /opt/sabero-academy -s /sbin/nologin sabero
sudo mkdir -p /opt/sabero-academy/current /etc/sabero-academy /var/www/letsencrypt
sudo tar -xzf /tmp/api-bundle.tgz -C /opt/sabero-academy/current
sudo bash -c 'cd /opt/sabero-academy/current/backend && NODE_OPTIONS=--max-old-space-size=384 npm ci --omit=dev'
sudo install -m 0640 -o root -g sabero /tmp/backend.env /etc/sabero-academy/backend.env
sudo chown -R sabero:sabero /opt/sabero-academy

# 4. systemd (solo API)
sudo install -m 0644 /tmp/sabero-academy-api.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now sabero-academy-api
sleep 3; curl -fsS http://127.0.0.1:3000/api/v1/health && echo

# 5. SELinux: nginx -> backend local
sudo setsebool -P httpd_can_network_connect 1 || true

# 6. nginx http, certificado, nginx https
sudo install -m 0644 /tmp/api-limits.conf /etc/nginx/conf.d/api-limits.conf
sudo install -m 0644 /tmp/api-http.conf /etc/nginx/conf.d/api.conf
sudo systemctl enable --now nginx && sudo nginx -t && sudo systemctl reload nginx
sudo certbot certonly --webroot -w /var/www/letsencrypt -d "$DOMAIN" -m "$EMAIL" --agree-tos --no-eff-email -n
sudo install -m 0644 /tmp/api-https.conf /etc/nginx/conf.d/api.conf
sudo nginx -t && sudo systemctl reload nginx
sudo systemctl enable --now certbot-renew.timer 2>/dev/null || true
echo OK
