# Knowledge Graph Assignment - Single Command Startup (Windows)
# Run this script to start everything: .\start.ps1
#
# If you get an execution policy error, run:
#   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

$ErrorActionPreference = "Stop"

# Change to script directory
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ScriptDir

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Knowledge Graph Assignment - Startup" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# ============================================
# 1. Pre-flight checks
# ============================================
Write-Host "🔍 Running pre-flight checks..." -ForegroundColor Yellow
Write-Host ""

# Check Docker
try {
    $null = Get-Command docker -ErrorAction Stop
    Write-Host "✅ Docker is installed" -ForegroundColor Green
} catch {
    Write-Host "❌ Docker is not installed!" -ForegroundColor Red
    Write-Host "   Please install Docker Desktop from: https://www.docker.com/products/docker-desktop" -ForegroundColor Red
    exit 1
}

# Check Docker is running
try {
    $dockerInfo = docker info 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Docker not running"
    }
    Write-Host "✅ Docker is running" -ForegroundColor Green
} catch {
    Write-Host "❌ Docker is not running!" -ForegroundColor Red
    Write-Host "   Please start Docker Desktop and try again." -ForegroundColor Red
    exit 1
}

# Check Docker Compose
$composeCmd = $null
try {
    $null = docker compose version 2>&1
    if ($LASTEXITCODE -eq 0) {
        $composeCmd = "docker compose"
        Write-Host "✅ Docker Compose is available" -ForegroundColor Green
    } else {
        throw "compose v2 not available"
    }
} catch {
    try {
        $null = docker-compose version 2>&1
        if ($LASTEXITCODE -eq 0) {
            $composeCmd = "docker-compose"
            Write-Host "✅ Docker Compose is available" -ForegroundColor Green
        } else {
            throw "compose v1 not available"
        }
    } catch {
        Write-Host "❌ Docker Compose is not available!" -ForegroundColor Red
        Write-Host "   Please install Docker Compose or update Docker Desktop." -ForegroundColor Red
        exit 1
    }
}

# Check available memory
try {
    $totalMemGB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)
    if ($totalMemGB -lt 8) {
        Write-Host "⚠️  Warning: Only ${totalMemGB}GB RAM detected. Recommended: 8GB+" -ForegroundColor Yellow
        Write-Host "   Consider using a smaller model (edit OLLAMA_MODEL in .env)" -ForegroundColor Yellow
    } else {
        Write-Host "✅ Memory: ${totalMemGB}GB available" -ForegroundColor Green
    }
} catch {
    # Ignore memory check errors
}

# Check ports
function Test-PortInUse {
    param([int]$Port, [string]$Service)

    $connections = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
    if ($connections) {
        Write-Host "❌ Port $Port is already in use (needed for $Service)" -ForegroundColor Red
        Write-Host "   Please stop the service using this port and try again." -ForegroundColor Red
        Write-Host "   Run: Get-NetTCPConnection -LocalPort $Port" -ForegroundColor Red
        return $true
    }
    return $false
}

$portsOK = $true
if (Test-PortInUse -Port 11434 -Service "Ollama") { $portsOK = $false }
if (Test-PortInUse -Port 7474 -Service "Neo4j Browser") { $portsOK = $false }
if (Test-PortInUse -Port 7687 -Service "Neo4j Bolt") { $portsOK = $false }

if ($portsOK) {
    Write-Host "✅ Required ports are available (11434, 7474, 7687)" -ForegroundColor Green
} else {
    exit 1
}

Write-Host ""

# ============================================
# 2. Create .env if it doesn't exist
# ============================================
if (-not (Test-Path ".env")) {
    Write-Host "📝 Creating .env file from env.example..." -ForegroundColor Yellow
    Copy-Item "env.example" ".env"
    Write-Host "✅ Created .env with default settings" -ForegroundColor Green
} else {
    Write-Host "✅ .env file exists" -ForegroundColor Green
}

Write-Host ""

# ============================================
# 3. Start Docker services
# ============================================
Write-Host "🐳 Starting Docker services..." -ForegroundColor Yellow
Write-Host ""

if ($composeCmd -eq "docker compose") {
    docker compose up -d ollama neo4j
} else {
    docker-compose up -d ollama neo4j
}

Write-Host ""
Write-Host "⏳ Waiting for services to be healthy..." -ForegroundColor Yellow

# Wait for Ollama to be healthy
$maxWait = 60
$waited = 0
while ($waited -lt $maxWait) {
    if ($composeCmd -eq "docker compose") {
        $status = docker compose ps ollama 2>&1
    } else {
        $status = docker-compose ps ollama 2>&1
    }
    if ($status -match "healthy") {
        break
    }
    Start-Sleep -Seconds 2
    $waited += 2
    Write-Host "   Waiting for Ollama... (${waited}s)"
}

if ($waited -ge $maxWait) {
    Write-Host "⚠️  Ollama is taking longer than expected to start." -ForegroundColor Yellow
    Write-Host "   Check logs with: docker-compose logs ollama" -ForegroundColor Yellow
}

# Wait for Neo4j to be healthy
$waited = 0
while ($waited -lt $maxWait) {
    if ($composeCmd -eq "docker compose") {
        $status = docker compose ps neo4j 2>&1
    } else {
        $status = docker-compose ps neo4j 2>&1
    }
    if ($status -match "healthy") {
        break
    }
    Start-Sleep -Seconds 2
    $waited += 2
    Write-Host "   Waiting for Neo4j... (${waited}s)"
}

Write-Host ""
Write-Host "✅ Services are starting!" -ForegroundColor Green

# ============================================
# 4. Check if model needs to be downloaded
# ============================================
Write-Host ""
Write-Host "🤖 Checking LLM model..." -ForegroundColor Yellow

# Read model from .env
$model = "llama3.2:3b"
if (Test-Path ".env") {
    $envContent = Get-Content ".env" | Where-Object { $_ -match "^OLLAMA_MODEL=" }
    if ($envContent) {
        $model = ($envContent -split "=", 2)[1].Trim()
    }
}
if ([string]::IsNullOrEmpty($model)) {
    $model = "llama3.2:3b"
}

# Give Ollama a moment to fully start
Start-Sleep -Seconds 5

# Check if model exists
try {
    $response = Invoke-RestMethod -Uri "http://localhost:11434/api/tags" -Method Get -ErrorAction Stop
    $modelExists = $response.models | Where-Object { $_.name -eq $model }
} catch {
    $modelExists = $null
}

if ($modelExists) {
    Write-Host "✅ Model '$model' is already downloaded" -ForegroundColor Green
} else {
    Write-Host "📥 Model '$model' needs to be downloaded..." -ForegroundColor Yellow
    Write-Host "   This will take 5-10 minutes on first run." -ForegroundColor Yellow
    Write-Host ""

    # Start ollama-init if not already running
    if ($composeCmd -eq "docker compose") {
        docker compose up -d ollama-init
    } else {
        docker-compose up -d ollama-init
    }

    Write-Host "   Downloading model (you can check progress with: docker-compose logs -f ollama-init)" -ForegroundColor Yellow
    Write-Host ""

    # Wait for model to download (with progress indicator)
    while ($true) {
        try {
            $response = Invoke-RestMethod -Uri "http://localhost:11434/api/tags" -Method Get -ErrorAction Stop
            $modelExists = $response.models | Where-Object { $_.name -eq $model }
            if ($modelExists) {
                Write-Host ""
                Write-Host "✅ Model '$model' downloaded successfully!" -ForegroundColor Green
                break
            }
        } catch {
            # API not ready yet
        }

        # Check if init container is still running
        if ($composeCmd -eq "docker compose") {
            $initStatus = docker compose ps ollama-init 2>&1
        } else {
            $initStatus = docker-compose ps ollama-init 2>&1
        }

        if ($initStatus -notmatch "Up") {
            # Check if it exited successfully
            if ($composeCmd -eq "docker compose") {
                $initStatusAll = docker compose ps -a ollama-init 2>&1
            } else {
                $initStatusAll = docker-compose ps -a ollama-init 2>&1
            }

            if ($initStatusAll -match "Exited \(0\)") {
                Write-Host ""
                Write-Host "✅ Model '$model' downloaded successfully!" -ForegroundColor Green
                break
            } else {
                Write-Host ""
                Write-Host "⚠️  Model download may have failed. Check: docker-compose logs ollama-init" -ForegroundColor Yellow
                break
            }
        }

        Write-Host -NoNewline "."
        Start-Sleep -Seconds 5
    }
}

# ============================================
# 5. Final status
# ============================================
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  🎉 Setup Complete!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Services running:" -ForegroundColor White
Write-Host "  • Ollama API:     http://localhost:11434" -ForegroundColor White
Write-Host "  • Neo4j Browser:  http://localhost:7474" -ForegroundColor White
Write-Host "  • Neo4j Bolt:     bolt://localhost:7687" -ForegroundColor White
Write-Host ""
Write-Host "Neo4j credentials: neo4j / password123" -ForegroundColor White
Write-Host ""
Write-Host "Next steps:" -ForegroundColor White
Write-Host "  1. Build your application" -ForegroundColor White
Write-Host "  2. See README.md for requirements" -ForegroundColor White
Write-Host "  3. View your graph at http://localhost:7474" -ForegroundColor White
Write-Host ""
Write-Host "Useful commands:" -ForegroundColor White
Write-Host "  • Stop services:  docker-compose down" -ForegroundColor White
Write-Host "  • View logs:      docker-compose logs -f" -ForegroundColor White
Write-Host "  • Restart:        .\start.ps1" -ForegroundColor White
Write-Host ""
