# Lab 7: Multi-Network Microservices, Volumes, and Bind Mounts

## Architecture

```
Browser -> frontend (8080:3000) -> [frontend-backend] -> backend (5000) -> [backend-notification] -> notification (5001)
```

- **frontend** is only on `frontend-backend`, so it cannot reach `notification`.
- **backend** is on both networks and acts as the only bridge between them.
- **notification** is only on `backend-notification` and publishes no port.

| Service | Port (container) | Network(s) | Storage |
|---|---|---|---|
| frontend | 3000 (published as 8080) | frontend-backend | none |
| backend | 5000 | frontend-backend, backend-notification | volume `backend-logs` -> `/app/logs`, bind mount `~/backend-data` -> `/app/data` |
| notification | 5001 | backend-notification | volume `notification-logs` -> `/app/logs` |

> All commands below are also collected in `run.sh`.

---

## 1. Clone the application

```bash
git clone https://github.com/Ibrahim-Adel15/MicroserviceApp.git
cd MicroserviceApp
```

## 2. Build the images

```bash
docker build -t frontend:v1 ./frontend
docker build -t backend:v1 ./backend
docker build -t notification:v1 ./notification
docker images
```

![Docker images](screenshots/01-images.png)

## 3. Create the networks

Two bridge networks with separate subnets.

```bash
docker network create --driver bridge --subnet 10.10.1.0/24 frontend-backend
docker network create --driver bridge --subnet 10.10.2.0/24 backend-notification
docker network ls
docker network inspect frontend-backend --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}'
docker network inspect backend-notification --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}'
```

![Networks](screenshots/02-networks.png)

## 4. Create the volumes and the host directory

```bash
docker volume create backend-logs
docker volume create notification-logs
mkdir -p ~/backend-data
docker volume ls | grep -E "DRIVER|logs"
ls -ld ~/backend-data
```

![Volumes and host directory](screenshots/03-volumes.png)

## 5. Run the containers

### Notification (on `backend-notification`)

```bash
docker run -d \
  --name notification \
  --network backend-notification \
  -v notification-logs:/app/logs \
  notification:v1
```

### Backend (on both networks)

`docker run` accepts one `--network`, so the backend starts on `frontend-backend` and the second network is attached afterwards.

```bash
docker run -d \
  --name backend \
  --network frontend-backend \
  -v backend-logs:/app/logs \
  -v ~/backend-data:/app/data \
  -e NOTIFICATION_URL=http://notification:5001/notify \
  backend:v1

docker network connect backend-notification backend
```

### Frontend (on `frontend-backend`, port 8080 published)

```bash
docker run -d \
  --name frontend \
  --network frontend-backend \
  -p 8080:3000 \
  -e BACKEND_URL=http://backend:5000 \
  frontend:v1
```

### Verify

```bash
docker ps
```

![Running containers](screenshots/04-ps.png)

```bash
docker inspect backend --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}'
```

The backend is attached to both networks:

![Backend networks](screenshots/05-backend-networks.png)

```bash
docker inspect backend --format '{{json .Mounts}}'
```

The volume and the bind mount are both attached:

![Backend mounts](screenshots/06-backend-mounts.png)

## 6. Test the application

Open `http://localhost:8080`, create a message, and check that it appears in the list.

![Web page with a message](screenshots/07-browser.png)

### Data persisted on the host (bind mount)

```bash
cat ~/backend-data/messages.json
```

![messages.json on the host](screenshots/08-messages-json.png)

### Backend logs

```bash
docker logs backend | tail
```

![Backend logs](screenshots/09-backend-logs.png)

### Notification received the message

```bash
docker exec notification cat /app/logs/notification.log
```

![Notification log](screenshots/10-notification-log.png)

---

## Key concepts

- **Network isolation:** the frontend cannot reach the notification service because they share no network.
- **Volumes vs bind mounts:** volumes (managed by Docker) are used for logs; a bind mount (a host folder I control) is used for backend data so I can read `messages.json` directly from the host.
- **Container DNS:** on user-defined bridge networks, containers reach each other by name (`backend`, `notification`).
- **`EXPOSE` vs `-p`:** `EXPOSE` only documents the port; `-p 8080:3000` actually publishes it to the host.
