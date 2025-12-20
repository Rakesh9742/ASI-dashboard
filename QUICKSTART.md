# Quick Start Guide

## Prerequisites

- Docker Desktop installed and running
- (Optional) Node.js 18+ and Flutter SDK 3.0+ for local development

## Starting the Application

### Option 1: Using Docker (Recommended)

1. **Start all services**:
   ```bash
   docker-compose up -d
   ```

2. **Check service status**:
   ```bash
   docker-compose ps
   ```

3. **View logs**:
   ```bash
   # All services
   docker-compose logs -f
   
   # Specific service
   docker-compose logs -f backend
   docker-compose logs -f frontend
   docker-compose logs -f postgres
   ```

4. **Access the application**:
   - **Frontend (Web)**: Open http://localhost:8080 in your browser
   - **Backend API**: http://localhost:3000
   - **API Health Check**: http://localhost:3000/health

5. **Stop services**:
   ```bash
   docker-compose down
   ```

6. **Stop and remove volumes** (clean slate):
   ```bash
   docker-compose down -v
   ```

## Local Development

### Backend Development

1. **Navigate to backend**:
   ```bash
   cd backend
   ```

2. **Install dependencies**:
   ```bash
   npm install
   ```

3. **Set up environment**:
   ```bash
   cp .env.example .env
   # Edit .env with your settings
   ```

4. **Start PostgreSQL** (if not using Docker):
   ```bash
   # Using Docker for just PostgreSQL
   docker run -d --name asi_postgres \
     -e POSTGRES_USER=asi_user \
     -e POSTGRES_PASSWORD=asi_password \
     -e POSTGRES_DB=asi_dashboard \
     -p 5432:5432 \
     postgres:15-alpine
   ```

5. **Run database migration**:
   ```bash
   psql -U asi_user -d asi_dashboard -f migrations/001_initial_schema.sql
   ```

6. **Start development server**:
   ```bash
   npm run dev
   ```

### Frontend Development

1. **Navigate to frontend**:
   ```bash
   cd frontend
   ```

2. **Get dependencies**:
   ```bash
   flutter pub get
   ```

3. **Run on different platforms**:
   ```bash
   # Web
   flutter run -d chrome
   
   # iOS (macOS only)
   flutter run -d ios
   
   # Android
   flutter run -d android
   ```

4. **Update API URL** (if backend is not on localhost:3000):
   - Edit `lib/services/api_service.dart`
   - Change the `baseUrl` getter default value

## Testing the API

### Using curl

```bash
# Health check
curl http://localhost:3000/health

# Get all chips
curl http://localhost:3000/api/chips

# Get dashboard stats
curl http://localhost:3000/api/dashboard/stats

# Create a chip
curl -X POST http://localhost:3000/api/chips \
  -H "Content-Type: application/json" \
  -d '{
    "name": "ASI-4000",
    "description": "New test chip",
    "architecture": "RISC-V",
    "process_node": "3nm",
    "status": "design"
  }'
```

## Troubleshooting

### Port Already in Use

If ports 3000, 5432, or 8080 are already in use:

1. Edit `docker-compose.yml`
2. Change the port mappings:
   ```yaml
   ports:
     - "3001:3000"  # Change 3000 to 3001
   ```

### Database Connection Issues

1. Check if PostgreSQL container is running:
   ```bash
   docker-compose ps postgres
   ```

2. Check PostgreSQL logs:
   ```bash
   docker-compose logs postgres
   ```

3. Restart the backend:
   ```bash
   docker-compose restart backend
   ```

### Frontend Not Loading

1. Check if backend is running:
   ```bash
   curl http://localhost:3000/health
   ```

2. Check browser console for CORS errors

3. Verify API URL in `frontend/lib/services/api_service.dart`

### Flutter Build Issues

1. Clean and rebuild:
   ```bash
   cd frontend
   flutter clean
   flutter pub get
   flutter build web
   ```

2. Check Flutter doctor:
   ```bash
   flutter doctor
   ```

## Next Steps

- Add authentication (JWT tokens are set up but not implemented)
- Add more dashboard widgets and charts
- Implement chip and design creation forms
- Add search and filtering capabilities
- Set up CI/CD pipeline




