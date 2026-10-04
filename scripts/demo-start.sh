#!/bin/bash
# Demo Startup Script for macOS/Linux/WSL
# This script starts the backend and creates a public tunnel for your presentation

echo "Benchly - Demo Startup"
echo "======================================="
echo ""

# Check if Docker is running
echo "Checking Docker..."
if docker version &>/dev/null; then
    echo "✓ Docker is running"
else
    echo "✗ Docker is not running. Please start Docker."
    exit 1
fi

# Start Docker Compose
echo ""
echo "Starting Docker Compose stack..."
docker compose up -d

echo "Waiting for services to start..."
sleep 5

# Check if backend is healthy
echo "Verifying backend health..."
max_attempts=30
attempt=0
while [ $attempt -lt $max_attempts ]; do
    response=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:4000/health)
    if [ "$response" = "200" ]; then
        echo "✓ Backend is healthy"
        break
    fi
    echo "Waiting for backend... ($((attempt+1))/$max_attempts)"
    sleep 1
    ((attempt++))
done

if [ "$response" != "200" ]; then
    echo "✗ Backend failed to start"
    docker compose logs
    exit 1
fi

# Check if npx is available
echo ""
echo "Setting up public tunnel..."
if ! command -v npx &>/dev/null; then
    echo "✗ npm/npx not found. Please install Node.js"
    exit 1
fi

echo "✓ npm/npx is available"
echo ""
echo "Starting tunnel to expose backend publicly..."
echo "This will keep running. Copy the URL below for Vercel:"
echo ""

# Start LocalTunnel
npx localtunnel --port 4000

echo ""
echo "Tunnel stopped. Backend is still running locally."
echo "Run: docker compose down"
echo "to stop all services."
