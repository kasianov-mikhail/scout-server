# Monitoring

Self-hosted uptime monitoring for the production deployment, using
[Uptime Kuma](https://github.com/louislam/uptime-kuma).

It runs as its own Docker Compose stack, separate from the application, so it is
not affected by app deploys. The file here is the source of truth; the server
copy lives in `/opt/monitoring` and is updated manually (the CI `deploy` job only
touches `/opt/scout`).

## Deploy / update

```sh
# DEPLOY_HOST is the production server (same host as the DEPLOY_HOST CI secret).
DEPLOY_HOST=root@your-server

# from this directory, copy the compose file to the server
scp docker-compose.yml "$DEPLOY_HOST":/opt/monitoring/docker-compose.yml

ssh "$DEPLOY_HOST" 'cd /opt/monitoring && docker compose pull && docker compose up -d'
```

## First-time setup (web UI)

Uptime Kuma's admin account and monitors are configured through its web UI on
first visit — there is no headless setup.

1. Open `http://<server>:3001` and create the admin account immediately
   (the instance is reachable over plain HTTP until a TLS proxy is added).
2. Add monitors:
   - **App — HTTP**: `http://app:8080/healthz`, expect status `200`.
     (Resolvable because Kuma is on the `scout_default` network.)
   - **Database — PostgreSQL**: connection string
     `postgres://scout:<DATABASE_PASSWORD>@db:5432/scout`.
     The password is in `/opt/scout/.env` on the server. `/healthz` does not
     touch the database, so this is the only signal that Postgres is healthy.
3. Add a **Telegram** notification (Settings → Notifications) and attach it to
   both monitors. Kuma fires a notification on both outage and recovery, and the
   built-in Telegram type's "Send Silently" toggle applies globally to all of
   its messages — so it cannot ring only on failures. Use one channel with
   "Send Silently" off (sound on outage and recovery alike). To mute recoveries
   specifically, use a **Webhook** notification pointing at a small relay that
   sets `disable_notification` per event instead.
