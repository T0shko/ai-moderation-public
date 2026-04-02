# AI Moderation App

A full-stack application for AI-powered content moderation with user management and sentiment analysis.

## Architecture

- **Backend**: Spring Boot (Java 17) with PostgreSQL
- **Frontend**: Flutter (mobile/web)
- **Database**: PostgreSQL with Liquibase migrations
- **Container**: Docker & Docker Compose

## Prerequisites

- Docker & Docker Compose
- Java 17
- Maven
- Flutter (for frontend development)

## Quick Start

1. **Clone and navigate to the project:**
   ```bash
   cd ai-moderation-app
   ```

2. **Start the application:**
   ```bash
   ./start.sh
   ```

   This will:
   - Start PostgreSQL in Docker
   - Run Liquibase migrations
   - Start the Spring Boot backend

3. **Start the Flutter frontend (in a new terminal):**
   ```bash
   ./frontend/start_web.sh
   ```

   This starts the Flutter web app on `http://localhost:4200`.

## Manual Setup

If you prefer to run components manually:

### Database Setup

```bash
# Start PostgreSQL
docker-compose up -d postgres

# Wait for database to be ready
sleep 10
```

### Backend Setup

```bash
cd backend

# Run Liquibase migrations
mvn liquibase:update

# Start Spring Boot application
mvn spring-boot:run
```

### Frontend Setup

```bash
cd frontend
flutter pub get
flutter run -d chrome --web-hostname 0.0.0.0 --web-port 4200
```

## Default Credentials

- **Username**: admin
- **Password**: admin123

## Database Configuration

- **Host**: localhost
- **Port**: 5432
- **Database**: aimoderation
- **Username**: postgres
- **Password**: password

## API Endpoints

- **Backend**: http://localhost:8080
- **Frontend (web)**: http://localhost:4200
- **Authentication**: POST /api/auth/signin
- **Comments**: GET /api/comments
- **Admin Panel**: GET /api/admin/*

## Development

### Database Migrations

Add new Liquibase changesets to:
```
backend/src/main/resources/db/changelog/
```

Update the master changelog:
```
backend/src/main/resources/db/changelog/db.changelog-master.xml
```

### Adding New Tables

1. Create a new XML file in the changelog directory
2. Add the changeset to the master changelog
3. Run migrations: `mvn liquibase:update`

## Stopping the Application

```bash
# Stop all services
docker-compose down

# Remove volumes (WARNING: deletes data)
docker-compose down -v
```

## Project Structure

```
├── backend/                 # Spring Boot application
│   ├── src/main/resources/
│   │   ├── db/changelog/   # Liquibase migrations
│   │   └── application.properties
│   └── pom.xml
├── frontend/               # Flutter application
├── docker-compose.yml      # Database services
└── start.sh               # Quick start script
```
