#!/usr/bin/env bash
# Lab 3: Creating a Docker Image for a Java Application
# Usage: ./run.sh
set -uo pipefail

REPO_URL="https://github.com/Ibrahim-Adel15/CalculatorMavenApp.git"
APP_DIR="CalculatorMavenApp"
PORT=8080

log()  { echo -e "\n\033[1;34m==> $*\033[0m"; }
fail() { echo -e "\033[1;31mERROR: $*\033[0m" >&2; exit 1; }

command -v docker >/dev/null || fail "docker is not installed"
command -v git    >/dev/null || fail "git is not installed"

# ---------------------------------------------------------------
# Clone
# ---------------------------------------------------------------
if [ ! -d "$APP_DIR" ]; then
  log "Cloning the repository"
  git clone "$REPO_URL" || fail "git clone failed"
fi
cd "$APP_DIR" || fail "cannot enter $APP_DIR"

# ---------------------------------------------------------------
# Helper: run a container, verify, then delete container + image
# ---------------------------------------------------------------
verify_and_cleanup() {
  local container="$1" image="$2"

  log "Running $container"
  docker rm -f "$container" >/dev/null 2>&1
  docker run -d --name "$container" -p ${PORT}:${PORT} "$image" || return 1
  sleep 8

  log "Logs of $container"
  docker logs "$container"

  log "Checking http://localhost:${PORT}"
  if curl -s -o /dev/null -w "HTTP status: %{http_code}\n" "http://localhost:${PORT}"; then
    :
  else
    echo "No HTTP response (this may be a console app, check the logs above)."
  fi

  log "Container status"
  docker ps -a --filter "name=$container"

  log "Deleting container $container and image $image"
  docker rm -f "$container" >/dev/null
  docker rmi "$image" >/dev/null
}

get_size() { docker image inspect "$1" --format '{{.Size}}'; }
human()    { numfmt --to=iec --suffix=B "$1" 2>/dev/null || echo "$1 bytes"; }

# ===============================================================
# Part 1: Build inside Docker
# ===============================================================
log "PART 1: Build inside Docker"

cat > Dockerfile.part1 <<'EOF'
FROM maven:3.9-eclipse-temurin-17

# Non-root user
RUN groupadd -r appgroup && useradd -r -g appgroup appuser

# Working directory
WORKDIR /app

# Copy source and build
COPY . .
RUN mvn package -DskipTests && chown -R appuser:appgroup /app

USER appuser
EXPOSE 8080

# Run the generated JAR (ignores original-*.jar)
CMD ["sh", "-c", "java -jar $(ls target/*.jar | grep -v original | head -n 1)"]
EOF

docker build -f Dockerfile.part1 -t app1 . || fail "Part 1 build failed"

SIZE1=$(get_size app1)
log "app1 size: $(human "$SIZE1")"
docker images app1

verify_and_cleanup container1 app1

# ===============================================================
# Part 2: Build locally
# ===============================================================
log "PART 2: Build locally"

command -v mvn  >/dev/null || fail "Maven (mvn) is not installed locally"
command -v java >/dev/null || fail "Java is not installed locally"

mvn clean package -DskipTests || fail "Local Maven build failed"

JAR_FILE=$(ls target/*.jar 2>/dev/null | grep -v original | head -n 1)
[ -n "$JAR_FILE" ] || fail "No JAR found in target/"
log "Using JAR: $JAR_FILE"

cat > Dockerfile.part2 <<'EOF'
FROM eclipse-temurin:17-jre

# Non-root user
RUN groupadd -r appgroup && useradd -r -g appgroup appuser

# Working directory
WORKDIR /app

# Copy the locally built JAR
ARG JAR_FILE
COPY ${JAR_FILE} app.jar
RUN chown appuser:appgroup app.jar

USER appuser
EXPOSE 8080

CMD ["java", "-jar", "app.jar"]
EOF

docker build -f Dockerfile.part2 --build-arg JAR_FILE="$JAR_FILE" -t app2 . \
  || fail "Part 2 build failed"

SIZE2=$(get_size app2)
log "app2 size: $(human "$SIZE2")"
docker images app2

verify_and_cleanup container2 app2

# ===============================================================
# Bonus: comparison
# ===============================================================
log "BONUS: Size comparison"
printf "%-8s %s\n" "app1" "$(human "$SIZE1")  (build inside Docker, Maven + JDK image)"
printf "%-8s %s\n" "app2" "$(human "$SIZE2")  (local build, JRE-only image)"

if [ "$SIZE1" -gt "$SIZE2" ]; then
  DIFF=$((SIZE1 - SIZE2))
  echo "app1 is larger by $(human "$DIFF")"
else
  DIFF=$((SIZE2 - SIZE1))
  echo "app2 is larger by $(human "$DIFF")"
fi

cat <<'EOF'

Why app1 is bigger:
  - Based on the Maven image (full JDK + Maven), not needed at runtime.
  - Contains source code, target/ output and downloaded dependencies.

Why app2 is smaller:
  - Uses a JRE-only image and contains just the final JAR.

Best of both: a multi-stage build (Maven stage to build, JRE stage to run).
EOF
