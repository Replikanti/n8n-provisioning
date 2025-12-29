# Použij Node.js Alpine jako base
FROM node:20-alpine

# Instaluj system dependencies
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
    curl \
    tini \
    su-exec \
    && rm -rf /var/cache/apk/*

# Nastav Puppeteer proměnné
ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true \
    PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium-browser \
    CHROME_BIN=/usr/bin/chromium-browser \
    CHROME_PATH=/usr/bin/chromium-browser

# Instaluj n8n globálně
RUN npm install -g n8n

# Vytvoř node uživatele a nastavit home directory
RUN addgroup -g 1000 node || true && \
    adduser -D -u 1000 -G node node || true && \
    mkdir -p /home/node/.n8n && \
    chown -R node:node /home/node

# Pracovní adresář
WORKDIR /home/node

# Zkopíruj vlastní entrypoint
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

# Nastav node jako default user
USER node

# Expose n8n port
EXPOSE 5678

# Entrypoint
ENTRYPOINT ["tini", "--", "/docker-entrypoint.sh"]
