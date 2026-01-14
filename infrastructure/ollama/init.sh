#!/bin/bash
# Ollama Model Initialization Script
# This script pulls the configured LLM model on first startup

set -e

# Use environment variable (set in docker-compose.yml with default)
MODEL="${OLLAMA_MODEL:-llama3.2:3b}"

echo "============================================"
echo "  Knowledge Graph Assignment - Ollama Init"
echo "============================================"
echo ""
echo "Configured model: $MODEL"
echo "Ollama host: $OLLAMA_HOST"
echo ""

# Wait for Ollama to be ready using ollama CLI
echo "Waiting for Ollama service to be ready..."
MAX_RETRIES=60
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if OLLAMA_HOST="http://$OLLAMA_HOST:11434" ollama list > /dev/null 2>&1; then
        echo "Ollama is ready!"
        break
    fi
    echo "  Ollama not ready yet, waiting... (attempt $((RETRY_COUNT + 1))/$MAX_RETRIES)"
    sleep 2
    RETRY_COUNT=$((RETRY_COUNT + 1))
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo "ERROR: Ollama did not become ready in time"
    exit 1
fi

echo ""

# Set OLLAMA_HOST for subsequent commands
export OLLAMA_HOST="http://$OLLAMA_HOST:11434"

# Check if model already exists
echo "Checking if model '$MODEL' is already downloaded..."

if ollama list 2>/dev/null | grep -q "$MODEL"; then
    echo "Model '$MODEL' already exists. Skipping download."
else
    echo "Downloading model '$MODEL'..."
    echo "This may take several minutes depending on your internet connection."
    echo ""
    ollama pull "$MODEL"
    echo ""
    echo "Model '$MODEL' downloaded successfully!"
fi

echo ""
echo "============================================"
echo "  Ollama initialization complete!"
echo "  Model '$MODEL' is ready to use."
echo "============================================"
