# Lab 8: Containerized Node.js and MySQL Stack (Docker Compose)

Run the iVolve Node.js app together with a MySQL database using a single `docker compose` command.

## Architecture

```
Browser -> localhost:3000 -> [ app (Node.js) ] --ivolve-net--> [ db (MySQL 8) ]
                                   |                               |
                              app_logs volume                 db_data volume
                              (/app/logs)                     (/var/lib/mysql)
```

## What's in this setup

| File | Purpose |
|---|---|
| `Dockerfile` | Builds the app image (Node 18 Alpine) |
| `docker-compose.yml` | Defines the `app` and `db` services, network, and volumes |
| `.env` | Holds the database password (not committed or copied into the image) |
| `.dockerignore` | Keeps `.env`, `node_modules`, and `.git` out of the image |

## Services

**app**
- Built from the `Dockerfile`
- Port `3000` mapped to the host
- Reads its DB settings from environment variables: `DB_HOST`, `DB_USER`, `DB_PASSWORD`, `DB_NAME`
- Logs are persisted in the `app_logs` volume at `/app/logs`

**db**
- Image: `mysql:8`
- Creates the `ivolve` database on first start (`MYSQL_DATABASE`)
- Data is persisted in the `db_data` volume at `/var/lib/mysql`

**Network:** both services share a custom network called `ivolve-net`, so the app reaches MySQL using the hostname `db`.

## How to run

1. Clone the repo:
   ```bash
   git clone https://github.com/Ibrahim-Adel15/iVolveApp.git
   cd iVolveApp
   ```
2. Create a `.env` file:
   ```
   DB_PASSWORD=ChangeMe123
   ```
3. Start the stack:
   ```bash
   docker compose up -d --build
   ```
4. Check that everything is running:
   ```bash
   docker compose ps
   docker compose logs -f app
   ```

## How to verify

| Check | Command | Expected |
|---|---|---|
| App is up | open `http://localhost:3000` | The iVolve website |
| DB connection | `curl http://localhost:3000/health` | Success message (app ran `SELECT 1` on MySQL) |
| Readiness | `curl http://localhost:3000/ready` | "ready" message |
| Database exists | `docker compose exec db mysql -uroot -p -e "SHOW DATABASES;"` | `ivolve` is listed |
| Volumes exist | `docker volume ls` | `db_data` and `app_logs` |
| Logs written | `docker compose exec app cat /app/logs/access.log` | Request log lines |

## Notes

- The app will not start its web server until it can connect to the `ivolve` database. It retries every 5 seconds, so it is fine if MySQL takes a moment to start.
- `docker compose down` keeps the data. `docker compose down -v` deletes the volumes (and the data).

## Build and push to Docker Hub

```bash
docker login
docker build -t <dockerhub-username>/ivolve-app:latest .
docker push <dockerhub-username>/ivolve-app:latest
```

## Stop the stack

```bash
docker compose down
```
