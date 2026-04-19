#!/usr/bin/env bash
# Usage: sudo ./ssl-setup.sh yourdomain.com your@email.com
set -euo pipefail

DOMAIN="${1:-yourdomain.com}"
EMAIL="${2:-your@email.com}"

apt install -y certbot python3-certbot-nginx

for CONF in s3.conf console.conf files.conf; do
    if [ -f "/etc/nginx/sites-available/${CONF}" ] && [ ! -L "/etc/nginx/sites-enabled/${CONF}" ]; then
        ln -s "/etc/nginx/sites-available/${CONF}" "/etc/nginx/sites-enabled/${CONF}"
    fi
done

nginx -t
systemctl reload nginx

certbot --nginx \
    -d "s3.${DOMAIN}" \
    -d "console.${DOMAIN}" \
    -d "files.${DOMAIN}" \
    --email "${EMAIL}" \
    --agree-tos \
    --non-interactive \
    --redirect

certbot renew --dry-run
echo "SSL setup complete for s3/console/files.${DOMAIN}"
