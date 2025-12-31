# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Docker-based n8n provisioning with **Redis queue mode** and Chromium/Puppeteer support. The setup uses BullMQ (Redis-backed queue) to distribute workflow executions across dedicated worker instances, significantly reducing PostgreSQL database load and costs.

## Architecture

### Queue Mode Multi-Instance Setup

The deployment runs four containerized services:

1. **Redis** (`n8n-redis`): BullMQ queue backend and caching layer
   - Port: Internal only (6379)
   - Database 0: Job queue
   - Database 1: Application cache
   - Persistence: AOF (append-only file) with 512MB memory limit

2. **n8n-main** (`n8n-main`): Web UI, API server, and trigger scheduler
   - Port: 5678 (localhost only)
   - Role: User interface, workflow management, API endpoints, **cron/schedule triggers**
   - Does NOT execute workflows (queues them to Redis instead)
   - Environment: `EXECUTIONS_MODE=queue`
   - Note: Triggers (cron, schedule, polling) must run on main - cannot be separated in n8n

3. **n8n-worker** (`n8n-worker`): Workflow execution engine
   - No exposed ports
   - Role: Pulls jobs from Redis queue and executes workflows
   - Can be scaled horizontally (see Scaling Workers section)
   - Command: `worker`
   - Environment: `EXECUTIONS_MODE=queue`

4. **n8n-webhook** (`n8n-webhook`): Webhook receiver
   - Port: 5679 (localhost only)
   - Role: Receives and processes incoming webhooks, queues executions to Redis
   - Command: `webhook`
   - Environment: `EXECUTIONS_MODE=queue`

### Supporting Components

- **Dockerfile**: Extends `n8nio/n8n:latest` with Chromium/Puppeteer support
- **docker-entrypoint.sh**: Auto-installs `n8n-nodes-puppeteer` on first run
- **docker-compose.yml**: Orchestrates all four services with proper dependencies
- **run-compose.sh**: Build and deployment automation with image pruning

### Why Queue Mode?

Queue mode moves workflow execution out of the PostgreSQL database into Redis:
- **Before**: All execution state, queuing, and coordination in PostgreSQL → expensive on Neon
- **After**: Lightweight job queue in Redis, only final results in PostgreSQL → ~90% reduction in DB operations
- **Benefit**: Horizontal scaling of workers, better fault tolerance, lower costs

## Common Commands

### Deployment and Management

```bash
# Primary deployment command (builds, prunes old images, starts stack)
./run-compose.sh
chmod +x run-compose.sh  # Make executable if needed

# View all running services
docker-compose ps

# View logs for specific service
docker-compose logs -f n8n-main
docker-compose logs -f n8n-worker
docker-compose logs -f n8n-webhook
docker-compose logs -f redis

# View logs for all services
docker-compose logs -f

# Restart specific service
docker-compose restart n8n-worker

# Stop entire stack
docker-compose down

# Stop stack and remove volumes (DESTRUCTIVE)
docker-compose down -v
```

### Manual Build and Run

```bash
# Build image without running
docker-compose build

# Start stack without rebuilding
docker-compose up -d

# Rebuild and restart specific service
docker-compose up -d --build n8n-worker
```

### Debugging and Monitoring

```bash
# Check Redis connection and stats
docker exec -it n8n-redis redis-cli ping
docker exec -it n8n-redis redis-cli INFO stats
docker exec -it n8n-redis redis-cli DBSIZE

# Monitor Redis queue in real-time
docker exec -it n8n-redis redis-cli MONITOR

# Check queue lengths (BullMQ uses specific key patterns)
docker exec -it n8n-redis redis-cli --scan --pattern "bull:*"
docker exec -it n8n-redis redis-cli KEYS "bull:*:waiting"

# Access n8n-worker shell for debugging
docker exec -it n8n-worker sh

# Check Puppeteer installation
docker exec -it n8n-worker which chromium-browser
docker exec -it n8n-worker chromium-browser --version

# View environment variables
docker exec -it n8n-main env | grep -E 'REDIS|QUEUE'
```

### Scaling Workers

To run multiple workers for increased throughput:

```bash
# Scale to 3 worker instances
docker-compose up -d --scale n8n-worker=3

# Scale back to 1 worker
docker-compose up -d --scale n8n-worker=1
```

**Note**: When scaling, docker-compose will name containers `n8n-worker-1`, `n8n-worker-2`, etc. Remove `container_name: n8n-worker` from `docker-compose.yml` before scaling, or scaling will fail.

## Configuration Details

### Database Connection

Uses **Neon PostgreSQL** (serverless) for:
- Workflow definitions
- Credentials storage
- Execution history (final results only, not intermediate state)
- User/settings data

Connection configured in `docker-compose.yml` environment variables for all services.

### Redis Configuration

- **Queue database**: DB 0 (BullMQ job queue)
- **Cache database**: DB 1 (application cache, 1-hour TTL)
- **Memory limit**: 512MB with LRU eviction (`allkeys-lru`)
- **Persistence**: AOF enabled for durability

### Reverse Proxy Requirements

The setup binds two ports to localhost and requires an external reverse proxy (Nginx, Caddy, Traefik) for SSL termination:

- **Port 5678** (n8n-main): Web UI and API → route `https://n8n.replikanti.xyz/*`
- **Port 5679** (n8n-webhook): Webhook ingress → route `https://n8n.replikanti.xyz/webhook/*` or use path-based routing

**Example Nginx config**:
```nginx
upstream n8n_ui {
    server 127.0.0.1:5678;
}

upstream n8n_webhook {
    server 127.0.0.1:5679;
}

server {
    listen 443 ssl http2;
    server_name n8n.replikanti.xyz;

    location /webhook {
        proxy_pass http://n8n_webhook;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location / {
        proxy_pass http://n8n_ui;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

### Volume Mounts

- `n8n_data`: Named volume at `/home/node/.n8n` (shared across all n8n instances)
- `redis_data`: Named volume at `/data` for Redis AOF persistence
- `/srv/n8n-ruian:/data/ruian`: Host directory for RUIAN (Czech address registry) data

**Important**: All n8n services share the same `n8n_data` volume for workflow definitions and credentials.

### Data Retention Policy

- Execution data saved on success, error, and manual runs
- Automatic pruning: max age 48 hours, max count 100 executions
- Queue jobs in Redis are ephemeral (no long-term retention)

## Modifying the Setup

### Adding Alpine Packages

Edit `Dockerfile:8-18` to add packages (Alpine Linux, not Debian):

```dockerfile
RUN apk update && apk add --no-cache \
    chromium \
    your-new-package
```

### Installing Additional n8n Community Nodes

Modify `docker-entrypoint.sh:7-13`:

```bash
npm install n8n-nodes-puppeteer n8n-nodes-package-name
```

### Adjusting Worker Concurrency

Workers process jobs concurrently. To increase/decrease concurrency per worker, add to `docker-compose.yml` under `n8n-worker` environment:

```yaml
- EXECUTIONS_PROCESS=own  # Run in separate process (more isolation)
- N8N_CONCURRENCY_PRODUCTION_LIMIT=10  # Max concurrent executions
```

### Changing Redis Memory Limit

Edit `docker-compose.yml:8`:

```yaml
command: redis-server --appendonly yes --maxmemory 1gb --maxmemory-policy allkeys-lru
```

### Using Environment Variables for Secrets

Instead of hardcoding credentials in `docker-compose.yml`, create a `.env` file (see `.env.example`):

```bash
cp .env.example .env
# Edit .env with real values
```

Then update `docker-compose.yml` to use `${VARIABLE_NAME}` syntax and add:

```yaml
env_file:
  - .env
```

### Updating n8n Version

Change `Dockerfile:2`:

```dockerfile
FROM n8nio/n8n:1.23.0  # Pin to specific version
```

Then rebuild: `docker-compose build --no-cache`

## Troubleshooting

### Workflows Not Executing

1. Check worker logs: `docker-compose logs n8n-worker`
2. Verify Redis connection: `docker exec -it n8n-worker env | grep REDIS`
3. Check queue has jobs: `docker exec -it n8n-redis redis-cli KEYS "bull:*"`

### Redis Out of Memory

1. Check memory usage: `docker exec -it n8n-redis redis-cli INFO memory`
2. Increase memory limit in `docker-compose.yml`
3. Consider reducing `CACHE_REDIS_TTL` or disabling cache

### Worker Crashes

Workers may crash with Chromium/Puppeteer workflows if resources are insufficient. Solutions:
- Reduce worker concurrency
- Increase Docker memory limits
- Scale horizontally (more workers, lower concurrency each)

### Webhook Not Receiving Requests

1. Verify webhook instance is running: `docker-compose ps`
2. Check reverse proxy routes to port 5679
3. Check logs: `docker-compose logs n8n-webhook`

## Important Notes

- **Credentials in git**: Database credentials are currently committed in `docker-compose.yml`. Use `.env` file for production.
- **Shared volume**: All n8n instances share `/home/node/.n8n`. This is intentional for workflow/credential sync.
- **Network isolation**: All services communicate via `n8n-network` bridge. Redis is not exposed to host.
- **Scaling limitations**: Can only scale workers and webhooks, not main instance (single UI).
- **PostgreSQL still required**: Queue mode reduces DB load but doesn't eliminate it. Workflows, credentials, and execution results still stored in PostgreSQL.
