# Začni s oficiálním n8n image
FROM n8nio/n8n:latest

# Přepni na root pro instalace
USER root

# Nainstaluj Chrome a závislosti
RUN apk update && apk add --no-cache \
    chromium \
    chromium-chromedriver \
    nss \
    freetype \
    freetype-dev \
    harfbuzz \
    ca-certificates \
    ttf-freefont \
    wget \
    curl

# Nastav Puppeteer proměnné
ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true \
    PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium-browser \
    CHROME_BIN=/usr/bin/chromium-browser \
    CHROME_PATH=/usr/bin/chromium-browser

# Zálohuj původní entrypoint a nahraď ho vlastním
RUN mv /docker-entrypoint.sh /docker-entrypoint-original.sh

COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

USER node
