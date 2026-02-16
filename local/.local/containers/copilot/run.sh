#!/bin/bash
# Helper script to run the Copilot sandbox container

# Default values
PROJECT_DIR="${1:-.}"
CONTAINER_NAME="copilot-sandbox"

# Check if image exists
if ! podman image exists "$CONTAINER_NAME"; then
    echo "Container image not found. Building..."
    podman build -t "$CONTAINER_NAME" -f Containerfile .
fi

# Run container with volume mount and GitHub token
echo "Starting Copilot sandbox..."
echo "Mounting: $PROJECT_DIR -> /workspace"
echo ""

podman run -it --rm \
  -v "$(realpath "$PROJECT_DIR"):/workspace:Z" \
  -e GH_TOKEN="$(gh auth token)" \
  "$CONTAINER_NAME"
