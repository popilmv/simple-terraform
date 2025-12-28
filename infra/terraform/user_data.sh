#!/bin/bash
set -euxo pipefail

LOG=/var/log/user-data.log
exec > >(tee -a "$LOG") 2>&1

# ---- IMDSv2 region ----
TOKEN="$(curl -sX PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")"
AWS_REGION="$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/placement/region)"

PROJECT_NAME="simple-app"
APP_DIR="/opt/${PROJECT_NAME}"

echo "AWS_REGION=${AWS_REGION}"
echo "PROJECT_NAME=${PROJECT_NAME}"
echo "APP_DIR=${APP_DIR}"

# ---- Packages ----
dnf -y update
dnf -y install docker awscli curl-minimal || true
command -v curl >/dev/null 2>&1 || dnf -y install curl-minimal

systemctl enable docker
systemctl start docker

# ---- Docker Compose plugin ----
mkdir -p /usr/local/lib/docker/cli-plugins
curl -fsSL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

COMPOSE="/usr/local/lib/docker/cli-plugins/docker-compose"

# ---- ECR registry ----
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
echo "ECR_REGISTRY=${ECR_REGISTRY}"

mkdir -p "${APP_DIR}/nginx"

# ---- env ----
cat > "${APP_DIR}/.env" <<EOF
AWS_REGION=${AWS_REGION}
ECR_REGISTRY=${ECR_REGISTRY}
PROJECT=${PROJECT_NAME}
TAG=latest
EOF

# ---- nginx config ----
cat > "${APP_DIR}/nginx/default.conf" <<'EOF'
server {
  listen 80;
  server_name _;

  location = /hello {
    add_header Content-Type text/plain;
    return 200 "hello\n";
  }

  location /api/ {
    proxy_pass http://backend:8080/;
  }

  location / {
    proxy_pass http://frontend:3000/;
  }
}
EOF

# ---- docker-compose.stub.yml ----
cat > "${APP_DIR}/docker-compose.stub.yml" <<'EOF'
services:
  nginx:
    image: nginx:1.25-alpine
    container_name: nginx
    ports:
      - "80:80"
    volumes:
      - ./nginx/default.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - frontend
      - backend
    restart: unless-stopped

  frontend:
    image: nginx:1.25-alpine
    container_name: frontend
    expose:
      - "3000"
    command:
      - sh
      - -c
      - |
        mkdir -p /usr/share/nginx/html;
        printf 'frontend stub ok\n' > /usr/share/nginx/html/index.html;
        sed -i 's/listen       80;/listen 3000;/' /etc/nginx/conf.d/default.conf;
        nginx -g 'daemon off;'
    restart: unless-stopped

  backend:
    image: hashicorp/http-echo:1.0
    container_name: backend
    expose:
      - "8080"
    command:
      - "-listen=:8080"
      - "-text={\"status\":\"backend stub ok\"}"
    restart: unless-stopped
EOF

# ---- docker-compose.ecr.yml ----
cat > "${APP_DIR}/docker-compose.ecr.yml" <<'EOF'
services:
  nginx:
    image: nginx:1.25-alpine
    container_name: nginx
    ports:
      - "80:80"
    volumes:
      - ./nginx/default.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - frontend
      - backend
    restart: unless-stopped

  frontend:
    image: ${ECR_REGISTRY}/${PROJECT}/frontend:${TAG}
    container_name: frontend
    expose:
      - "3000"
    restart: unless-stopped

  backend:
    image: ${ECR_REGISTRY}/${PROJECT}/backend:${TAG}
    container_name: backend
    expose:
      - "8080"
    depends_on:
      - db
    restart: unless-stopped

  db:
    image: postgres:16-alpine
    container_name: db
    environment:
      - POSTGRES_DB=app
      - POSTGRES_USER=app
      - POSTGRES_PASSWORD=app_password
    volumes:
      - db_data:/var/lib/postgresql/data
    restart: unless-stopped

volumes:
  db_data:
EOF

# ---- ECR login (optional; don't fail if ECR not ready) ----
aws ecr get-login-password --region "${AWS_REGION}" | \
  docker login --username AWS --password-stdin "${ECR_REGISTRY}" || true

cd "${APP_DIR}"

# ---- Decide which compose to use ----

FRONT_OK=0
BACK_OK=0

aws ecr describe-images --region "${AWS_REGION}" \
  --repository-name "${PROJECT_NAME}/frontend" \
  --image-ids imageTag=latest >/dev/null 2>&1 && FRONT_OK=1 || true

aws ecr describe-images --region "${AWS_REGION}" \
  --repository-name "${PROJECT_NAME}/backend" \
  --image-ids imageTag=latest >/dev/null 2>&1 && BACK_OK=1 || true

if [ "$FRONT_OK" -eq 1 ] && [ "$BACK_OK" -eq 1 ]; then
  echo "ECR images found -> using docker-compose.ecr.yml"
  COMPOSE_FILE="docker-compose.ecr.yml"
else
  echo "ECR images not found -> using docker-compose.stub.yml"
  COMPOSE_FILE="docker-compose.stub.yml"
fi

# ---- Bring up (always) ----
$COMPOSE --env-file .env -f "${COMPOSE_FILE}" up -d

echo "DONE. Local checks:"
curl -i http://localhost/hello || true
