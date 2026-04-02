#!/bin/bash

# Load environment variables from .env
if [ -f .env ]; then
    echo "📄 Loading environment variables from .env file..."
    export $(grep -v '^#' .env | xargs)
fi

# AI Moderation App - Start Script
echo "🚀 Starting AI Moderation App..."

# Start PostgreSQL with Docker Compose
echo "📦 Starting PostgreSQL database..."
docker-compose up -d postgres

# Wait for PostgreSQL to be ready
echo "⏳ Waiting for PostgreSQL to be ready..."
sleep 10

# Check if PostgreSQL is ready
until docker-compose exec postgres pg_isready -U postgres > /dev/null 2>&1; do
    echo "⏳ Waiting for PostgreSQL..."
    sleep 2
done

echo "✅ PostgreSQL is ready!"

# Run Liquibase migrations
echo "🛠️ Running database migrations with Liquibase..."
cd backend
mvn resources:resources liquibase:update

# Kill any process listening on port 8080
echo "🧹 Checking for existing processes on port 8080..."
if lsof -Pi :8080 -sTCP:LISTEN -t >/dev/null ; then
    echo "⚠️ Port 8080 is in use. Terminating existing process..."
    lsof -Pi :8080 -sTCP:LISTEN -t | xargs kill -9
fi

# Start the Spring Boot application
echo "🚀 Starting Spring Boot backend..."
mvn spring-boot:run &

# Go back to root directory
cd ..

echo "✅ Backend started on http://localhost:8080"
echo "✅ Database available on localhost:5432"
echo "📱 Frontend web can be started on port 4200 with: ./frontend/start_web.sh"
echo ""
echo "Default admin credentials:"
echo "Username: admin"
echo "Password: admin123"
echo ""
echo "To stop everything: docker-compose down"
