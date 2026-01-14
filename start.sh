#!/bin/bash
# Knowledge Graph Assignment - Single Command Startup
# Run this script to start everything: ./start.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "============================================"
echo "  Knowledge Graph Assignment - Startup"
echo "============================================"
echo ""

# ============================================
# 1. Pre-flight checks
# ============================================
echo "🔍 Running pre-flight checks..."
echo ""

# Check Docker
if ! command -v docker &> /dev/null; then
    echo "❌ Docker is not installed!"
    echo "   Please install Docker Desktop from: https://www.docker.com/products/docker-desktop"
    exit 1
fi
echo "✅ Docker is installed"

# Check Docker is running
if ! docker info &> /dev/null; then
    echo "❌ Docker is not running!"
    echo "   Please start Docker Desktop and try again."
    exit 1
fi
echo "✅ Docker is running"

# Check Docker Compose
if ! docker compose version &> /dev/null && ! docker-compose version &> /dev/null; then
    echo "❌ Docker Compose is not available!"
    echo "   Please install Docker Compose or update Docker Desktop."
    exit 1
fi
echo "✅ Docker Compose is available"

# Check available memory (warn if less than 8GB)
if command -v free &> /dev/null; then
    TOTAL_MEM=$(free -g | awk '/^Mem:/{print $2}')
elif command -v sysctl &> /dev/null; then
    TOTAL_MEM=$(($(sysctl -n hw.memsize) / 1024 / 1024 / 1024))
else
    TOTAL_MEM=0
fi

if [ "$TOTAL_MEM" -gt 0 ]; then
    if [ "$TOTAL_MEM" -lt 8 ]; then
        echo "⚠️  Warning: Only ${TOTAL_MEM}GB RAM detected. Recommended: 8GB+"
        echo "   Consider using a smaller model (edit OLLAMA_MODEL in .env)"
    else
        echo "✅ Memory: ${TOTAL_MEM}GB available"
    fi
fi

# Check ports (only detect actual listeners, not closed connections)
check_port() {
    local port=$1
    local service=$2
    # Check if something is actually LISTENING on this port
    if lsof -i :$port -sTCP:LISTEN &> /dev/null 2>&1; then
        echo "❌ Port $port is already in use (needed for $service)"
        echo "   Please stop the service using this port and try again."
        echo "   Run: lsof -i :$port"
        return 1
    fi
    return 0
}

PORTS_OK=true
check_port 11434 "Ollama" || PORTS_OK=false
check_port 7474 "Neo4j Browser" || PORTS_OK=false  
check_port 7687 "Neo4j Bolt" || PORTS_OK=false

if [ "$PORTS_OK" = true ]; then
    echo "✅ Required ports are available (11434, 7474, 7687)"
else
    exit 1
fi

echo ""

# ============================================
# 2. Create .env if it doesn't exist
# ============================================
if [ ! -f ".env" ]; then
    echo "📝 Creating .env file from env.example..."
    cp env.example .env
    echo "✅ Created .env with default settings"
else
    echo "✅ .env file exists"
fi

echo ""

# ============================================
# 3. Start Docker services
# ============================================
echo "🐳 Starting Docker services..."
echo ""

# Use docker compose (v2) or docker-compose (v1)
if docker compose version &> /dev/null; then
    COMPOSE_CMD="docker compose"
else
    COMPOSE_CMD="docker-compose"
fi

$COMPOSE_CMD up -d ollama neo4j

echo ""
echo "⏳ Waiting for services to be healthy..."

# Wait for Ollama to be healthy
MAX_WAIT=60
WAITED=0
while [ $WAITED -lt $MAX_WAIT ]; do
    if $COMPOSE_CMD ps ollama 2>/dev/null | grep -q "healthy"; then
        break
    fi
    sleep 2
    WAITED=$((WAITED + 2))
    echo "   Waiting for Ollama... (${WAITED}s)"
done

if [ $WAITED -ge $MAX_WAIT ]; then
    echo "⚠️  Ollama is taking longer than expected to start."
    echo "   Check logs with: docker-compose logs ollama"
fi

# Wait for Neo4j to be healthy
WAITED=0
while [ $WAITED -lt $MAX_WAIT ]; do
    if $COMPOSE_CMD ps neo4j 2>/dev/null | grep -q "healthy"; then
        break
    fi
    sleep 2
    WAITED=$((WAITED + 2))
    echo "   Waiting for Neo4j... (${WAITED}s)"
done

echo ""
echo "✅ Services are starting!"

# ============================================
# 4. Check if model needs to be downloaded
# ============================================
echo ""
echo "🤖 Checking LLM model..."

# Read model from .env
MODEL=$(grep OLLAMA_MODEL .env 2>/dev/null | cut -d= -f2 || echo "llama3.2:3b")
MODEL=${MODEL:-"llama3.2:3b"}

# Check if model exists
sleep 5  # Give Ollama a moment to fully start
if curl -s http://localhost:11434/api/tags 2>/dev/null | grep -q "\"$MODEL\""; then
    echo "✅ Model '$MODEL' is already downloaded"
else
    echo "📥 Model '$MODEL' needs to be downloaded..."
    echo "   This will take 5-10 minutes on first run."
    echo ""
    
    # Start ollama-init if not already running
    $COMPOSE_CMD up -d ollama-init
    
    echo "   Downloading model (you can check progress with: docker-compose logs -f ollama-init)"
    echo ""
    
    # Wait for model to download (with progress indicator)
    while true; do
        if curl -s http://localhost:11434/api/tags 2>/dev/null | grep -q "\"$MODEL\""; then
            echo ""
            echo "✅ Model '$MODEL' downloaded successfully!"
            break
        fi
        
        # Check if init container is still running
        if ! $COMPOSE_CMD ps ollama-init 2>/dev/null | grep -q "Up"; then
            # Check if it exited successfully
            if $COMPOSE_CMD ps -a ollama-init 2>/dev/null | grep -q "Exited (0)"; then
                echo ""
                echo "✅ Model '$MODEL' downloaded successfully!"
                break
            else
                echo ""
                echo "⚠️  Model download may have failed. Check: docker-compose logs ollama-init"
                break
            fi
        fi
        
        echo -n "."
        sleep 5
    done
fi

# ============================================
# 5. Final status
# ============================================
echo ""
echo "============================================"
echo "  🎉 Setup Complete!"
echo "============================================"
echo ""
echo "Services running:"
echo "  • Ollama API:     http://localhost:11434"
echo "  • Neo4j Browser:  http://localhost:7474"
echo "  • Neo4j Bolt:     bolt://localhost:7687"
echo ""
echo "Neo4j credentials: neo4j / password123"
echo ""
echo "Next steps:"
echo "  1. Build your application"
echo "  2. See README.md for requirements"
echo "  3. View your graph at http://localhost:7474"
echo ""
echo "Useful commands:"
echo "  • Stop services:  docker-compose down"
echo "  • View logs:      docker-compose logs -f"
echo "  • Restart:        ./start.sh"
echo ""
