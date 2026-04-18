#!/usr/bin/env bash
# ============================================================
# ListenAI HW2 - Automated Docker Experiment Script
# Run this AFTER Docker Desktop is running and `docker compose up -d --build` is done
# ============================================================

set -e
cd "$(dirname "$0")"

echo "======================================================"
echo "  ListenAI Docker Experiments"
echo "======================================================"

# -------------------------------------------------------
# TASK 2: Import data into the volume
# -------------------------------------------------------
echo ""
echo "[Task 2] Importing posts.csv into the volume..."
docker compose --profile init run --rm import

# -------------------------------------------------------
# TASK 3.1: Image sizes
# -------------------------------------------------------
echo ""
echo "[Task 3.1] Image sizes for all services:"
docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" | grep "listen-ai"

# -------------------------------------------------------
# TASK 3.2: Build time comparison - correct vs swapped order
# -------------------------------------------------------
echo ""
echo "[Task 3.2] Build time comparison (layer caching)"

# Make a tiny change to trigger rebuild
echo "# cache test $(date)" >> frontend/app.py

echo ""
echo "--- [3.2-A] Correct order (deps first, code second) ---"
docker build --no-cache -f frontend/Dockerfile -t listen-ai-frontend:correct ./frontend 2>&1 | grep -E "Step|STEP|=>|real|elapsed|#" | tail -20
time docker build -f frontend/Dockerfile -t listen-ai-frontend:correct-cached ./frontend 2>&1 | tail -5

echo ""
# Create a swapped-order Dockerfile for comparison
cat > /tmp/Dockerfile.swapped <<'EOF'
FROM python:3.11-slim

WORKDIR /app

# SWAPPED: Copy code first, then install deps (bad for caching)
COPY . .
RUN pip install --no-cache-dir -r requirements.txt

EXPOSE 8501
CMD ["streamlit", "run", "app.py", "--server.port=8501", "--server.address=0.0.0.0"]
EOF

echo "--- [3.2-B] Swapped order (code first, deps second) ---"
docker build --no-cache -f /tmp/Dockerfile.swapped -t listen-ai-frontend:swapped-nocache ./frontend 2>&1 | tail -5

# Make another small change to app.py
echo "# cache test 2 $(date)" >> frontend/app.py

echo ""
echo "--- [3.2-C] Correct order, code changed (cache HIT on deps layer) ---"
time docker build -f frontend/Dockerfile -t listen-ai-frontend:correct-change ./frontend 2>&1 | tail -5

echo ""
echo "--- [3.2-D] Swapped order, code changed (cache MISS - must reinstall deps) ---"
time docker build -f /tmp/Dockerfile.swapped -t listen-ai-frontend:swapped-change ./frontend 2>&1 | tail -5

# Revert the test changes
git checkout frontend/app.py

# -------------------------------------------------------
# TASK 3.3: python vs python-slim base image
# -------------------------------------------------------
echo ""
echo "[Task 3.3] Base image comparison: python vs python-slim"

cat > /tmp/Dockerfile.fullpython <<'EOF'
FROM python:3.11

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
EXPOSE 8501
CMD ["streamlit", "run", "app.py", "--server.port=8501", "--server.address=0.0.0.0"]
EOF

echo "--- Building with python:3.11 (full) ---"
time docker build --no-cache -f /tmp/Dockerfile.fullpython -t listen-ai-frontend:full ./frontend 2>&1 | tail -5

echo "--- Building with python:3.11-slim ---"
time docker build --no-cache -f frontend/Dockerfile -t listen-ai-frontend:slim ./frontend 2>&1 | tail -5

echo ""
echo "--- Image size comparison ---"
docker images --format "table {{.Repository}}:{{.Tag}}\t{{.Size}}" | grep "listen-ai-frontend"

# -------------------------------------------------------
# TASK 3.7: docker ps (all services)
# -------------------------------------------------------
echo ""
echo "[Task 2.7] docker ps with compose filter:"
docker ps --all --filter label=com.docker.compose.project

echo ""
echo "======================================================"
echo "  All experiments complete!"
echo "======================================================"
