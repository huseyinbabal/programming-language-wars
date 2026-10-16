#!/usr/bin/env bash
# One-time setup of the benchmark machine (Ubuntu 24.04, 8 dedicated vCPUs), run as root:
#   DOMAIN=plw.huseyinbabal.dev REPO=git@github.com:huseyinbabal/programming-language-wars.git bash setup.sh
# The repository is private, so the machine reads it with a read-only deploy key (/root/.ssh/plw_deploy).
# Only ports 22, 80 and 443 are open; Grafana, Prometheus and cAdvisor stay on the Docker network.
set -euo pipefail
: "${DOMAIN:?}" "${REPO:?}"
export DEBIAN_FRONTEND=noninteractive
cloud-init status --wait >/dev/null || true

apt-get update -qq && apt-get install -y -qq ca-certificates curl git ufw python3 >/dev/null
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" > /etc/apt/sources.list.d/docker.list
apt-get update -qq && apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin >/dev/null

ufw allow 22/tcp >/dev/null; ufw allow 80/tcp >/dev/null; ufw allow 443/tcp >/dev/null; ufw --force enable >/dev/null

if [ ! -f /root/.ssh/plw_deploy ]; then
  ssh-keygen -q -t ed25519 -N '' -C "plw-machine" -f /root/.ssh/plw_deploy
  echo "Add this key as a read-only deploy key on GitHub, then run setup.sh again:"; cat /root/.ssh/plw_deploy.pub; exit 0
fi
cat > /root/.ssh/config <<EOF
Host github.com
  IdentityFile /root/.ssh/plw_deploy
  StrictHostKeyChecking accept-new
EOF
[ -d /opt/plw ] || git clone -q "$REPO" /opt/plw

if [ ! -f /opt/plw/stack/.env ]; then
  sed -e "s|^GF_ADMIN_PASSWORD=.*|GF_ADMIN_PASSWORD=$(openssl rand -hex 16)|" \
      -e "s|^SITE_ADDRESS=.*|SITE_ADDRESS=$DOMAIN|" -e "s|^PUBLIC_URL=.*|PUBLIC_URL=https://$DOMAIN|" \
      -e "s|^HTTP_PORT=.*|HTTP_PORT=80|" -e "s|^HTTPS_PORT=.*|HTTPS_PORT=443|" \
      /opt/plw/stack/.env.example > /opt/plw/stack/.env
  chmod 600 /opt/plw/stack/.env
fi

docker compose -f /opt/plw/stack/compose.yml --env-file /opt/plw/stack/.env up -d --build
install -m 0644 /opt/plw/deploy/plw-deployer.service /etc/systemd/system/plw-deployer.service
systemctl daemon-reload && systemctl enable -q --now plw-deployer
echo "up: https://$DOMAIN"
