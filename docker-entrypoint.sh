#!/bin/sh
set -e

# Vytvoř nodes složku, pokud neexistuje
mkdir -p /home/node/.n8n/nodes

# Nainstaluj puppeteer node, pokud ještě není
if [ ! -d "/home/node/.n8n/nodes/node_modules/n8n-nodes-puppeteer" ]; then
  echo "Installing n8n-nodes-puppeteer..."
  cd /home/node/.n8n/nodes
  npm install n8n-nodes-puppeteer
  echo "Installation complete!"
fi

# Spusť původní entrypoint
exec /docker-entrypoint-original.sh "$@"
