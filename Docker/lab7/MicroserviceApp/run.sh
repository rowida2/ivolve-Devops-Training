#!/bin/bash
# Lab 7: Multi-Network Microservices, Volumes, and Bind Mounts
# Usage:
#   ./run.sh         -> build and run everything
#   ./run.sh clean   -> remove containers, networks, and volumes created by this lab

set -e

HOST_DATA_DIR="$HOME/backend-data"

if [ "$1" = "clean" ]; then
  echo "Cleaning up..."
  docker rm -f frontend backend notification 2>/dev/null || true
  docker network rm frontend-backend backend-notification 2>/dev/null || true
  docker volume rm backend-logs notification-logs 2>/dev/null || true
  echo "Done. (Host directory $HOST_DATA_DIR was kept on purpose.)"
  exit 0
fi

# 1) Build images (run this script from inside the MicroserviceApp folder)
echo "==> Building images"
docker build -t frontend:v1 ./frontend
docker build -t backend:v1 ./backend
docker build -t notification:v1 ./notification

# 2) Two bridge networks with separate subnets
echo "==> Creating networks"
docker network create --driver bridge --subnet 10.10.1.0/24 frontend-backend
docker network create --driver bridge --subnet 10.10.2.0/24 backend-notification

# 3) Two volumes for logs
echo "==> Creating volumes"
docker volume create backend-logs
docker volume create notification-logs

# 4) Host directory for the bind mount (backend data)
echo "==> Creating host directory"
mkdir -p "$HOST_DATA_DIR"

# 5) Notification: on backend-notification only
echo "==> Running notification"
docker run -d \
  --name notification \
  --network backend-notification \
  -v notification-logs:/app/logs \
  notification:v1

# 6) Backend: starts on frontend-backend, then connected to backend-notification
echo "==> Running backend"
docker run -d \
  --name backend \
  --network frontend-backend \
  -v backend-logs:/app/logs \
  -v "$HOST_DATA_DIR":/app/data \
  -e NOTIFICATION_URL=http://notification:5001/notify \
  backend:v1
docker network connect backend-notification backend

# 7) Frontend: on frontend-backend only, port 8080 published
echo "==> Running frontend"
docker run -d \
  --name frontend \
  --network frontend-backend \
  -p 8080:3000 \
  -e BACKEND_URL=http://backend:5000 \
  frontend:v1

echo "==> All done. Open http://localhost:8080"
docker ps
