# Knowledge Graph Builder - Home Assignment

Build a web application that creates a knowledge graph from a webpage using LLMs.

## Overview

Your task is to build a full-stack application that:

1. Accepts a URL as input via a web interface
2. Fetches the webpage HTML (scraping utility is provided)
3. Uses an LLM to identify entities and relationships from the content
4. Stores the resulting knowledge graph in Neo4j
5. Allows viewing the graph via Neo4j Browser

## Target Content

For this assignment, you will extract a knowledge graph from the **Pollard Middle School Building Project** page:

```
https://sites.google.com/needham.k12.ma.us/pollardbuildingproject/past-meetings-materials
```

## Quick Start

### Prerequisites

- **Docker Desktop** installed and running
- **8GB+ RAM** recommended (16GB for best performance)
- Ports **11434**, **7474**, **7687** available

### One-Command Setup

**macOS / Linux:**
```bash
./start.sh
```

**Windows (PowerShell):**
```powershell
.\start.ps1
```

> **Note for Windows users:** If you get an execution policy error, first run:
> ```powershell
> Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
> ```

That's it! The script will:
- ✅ Check all prerequisites
- ✅ Create configuration files
- ✅ Start Docker services
- ✅ Download the LLM model (first run only, ~5-10 min)

### Manual Setup (Alternative)

If you prefer manual setup:

```bash
# 1. Copy environment config
cp env.example .env

# 2. Start services
docker-compose up -d

# 3. Wait for model download (first run only)
docker-compose logs -f ollama-init
```

### Verify Services

Once running, you should have access to:

| Service | URL | Credentials |
|---------|-----|-------------|
| Ollama API | http://localhost:11434 | - |
| Neo4j Browser | http://localhost:7474 | neo4j / password123 |
| Neo4j Bolt | bolt://localhost:7687 | neo4j / password123 |

## Build Your Application

Create an application that:

- Provides a web UI for URL input
- Parses the HTML and extracts meaningful content
- Uses the LLM to identify entities and relationships
- Stores them in Neo4j
- Displays a link to view the graph in Neo4j Browser

## Provided Utilities

We've included a simple HTML fetching utility:

### Python

```python
from provided.scraper import fetch_html

html = fetch_html("https://example.com")
```

### Node.js

```javascript
const { fetchHtml } = require('./provided/scraper.js');

const html = await fetchHtml('https://example.com');
```

## API Reference

### Ollama (LLM)

```bash
# Generate completion
curl http://localhost:11434/api/generate -d '{
  "model": "llama3.2:3b",
  "prompt": "Your prompt here...",
  "stream": false
}'

# Chat endpoint
curl http://localhost:11434/api/chat -d '{
  "model": "llama3.2:3b",
  "messages": [{"role": "user", "content": "Your message..."}],
  "stream": false
}'
```

### Neo4j

```python
from neo4j import GraphDatabase
driver = GraphDatabase.driver("bolt://localhost:7687", auth=("neo4j", "password123"))

with driver.session() as session:
    session.run("CREATE (n:Entity {name: 'Example'}) RETURN n")
```

## Your Deliverables

1. **Working Application** - Your implementation
2. **Updated SUBMISSION.md** - Document your approach
3. **Graph Schema** - Your chosen entity types and relationships
4. **Run Instructions** - How to start your application

### Graph Design (Important!)

Design your own graph schema. You need to:

- Analyze the webpage content
- Identify meaningful entity types
- Define relationships between entities
- Decide what properties each entity should have

Document your reasoning in SUBMISSION.md.

## Evaluation Criteria

See `docs/evaluation-criteria.md` for details.

**In brief:**
- Working end-to-end solution
- Reasonable graph schema with meaningful relationships
- Clean, readable code
- Good documentation

## Time Expectation

**4-6 hours** total:

| Task | Time |
|------|------|
| Graph schema design | 30-45 min |
| LLM prompt engineering | 1.5-2 hrs |
| Neo4j integration | 45 min - 1 hr |
| Web UI | 1-1.5 hrs |
| Documentation | 30 min |

## Troubleshooting

### "Docker is not running"
Start Docker Desktop and wait for it to fully initialize.

### "Port already in use"
Another service is using the required port. Find and stop it:

**macOS / Linux:**
```bash
# Find what's using a port (e.g., 11434)
lsof -i :11434
# Kill it
kill -9 <PID>
```

**Windows (PowerShell):**
```powershell
# Find what's using a port (e.g., 11434)
Get-NetTCPConnection -LocalPort 11434
# Kill it (replace <PID> with the OwningProcess from above)
Stop-Process -Id <PID> -Force
```

### Model download is slow/stuck
Check download progress:
```bash
docker-compose logs -f ollama-init
```

If stuck, restart:
```bash
docker-compose down
docker-compose up -d
```

### Out of memory errors
Use a smaller model. Edit `.env`:
```
OLLAMA_MODEL=llama3.2:1b
```

Then restart:
```bash
docker-compose down
docker volume rm graph-home-assignemnt-jun_ollama_data
./start.sh        # or .\start.ps1 on Windows
```

### Neo4j won't start
Check logs:
```bash
docker-compose logs neo4j
```

Common fix - clear data and restart:
```bash
docker-compose down
docker volume rm graph-home-assignemnt-jun_neo4j_data
./start.sh        # or .\start.ps1 on Windows
```

### Scraper can't fetch URL
Some networks block automated requests. Try:
- Disabling VPN
- Using a different network
- The URL may be temporarily unavailable

## Useful Commands

**macOS / Linux:**
```bash
# Start everything
./start.sh

# Stop services
docker-compose down

# View logs
docker-compose logs -f

# Restart a specific service
docker-compose restart ollama

# Check service status
docker-compose ps

# Full reset (removes all data)
docker-compose down -v
./start.sh
```

**Windows (PowerShell):**
```powershell
# Start everything
.\start.ps1

# Stop services
docker-compose down

# View logs
docker-compose logs -f

# Restart a specific service
docker-compose restart ollama

# Check service status
docker-compose ps

# Full reset (removes all data)
docker-compose down -v
.\start.ps1
```

## Need Help?

- Check `docs/hints.md` for progressive hints
- Review the provided scraper utility
- Test queries in Neo4j Browser first

## Submission

1. Update `SUBMISSION.md` with your notes
2. Include clear instructions to run your app
3. Commit and push your solution

Good luck!
