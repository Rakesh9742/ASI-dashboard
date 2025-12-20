# ASI Chip Design Dashboard

A comprehensive dashboard for chip design management, built with TypeScript backend and Flutter frontend supporting web, iOS, and Android platforms.

## Architecture

- **Backend**: TypeScript + Express.js + PostgreSQL
- **Frontend**: Flutter (Web, iOS, Android)
- **Database**: PostgreSQL (Database: ASI, User: postgres, Password: root)
- **Containerization**: Docker & Docker Compose
- **Authentication**: JWT-based with role-based access control

## Project Structure

```
ASI dashboard/
├── backend/          # TypeScript backend API
│   ├── src/
│   │   ├── config/   # Database configuration
│   │   ├── routes/   # API routes
│   │   └── index.ts  # Entry point
│   ├── migrations/   # Database migrations
│   └── Dockerfile
├── frontend/         # Flutter application
│   ├── lib/
│   │   ├── screens/  # UI screens
│   │   ├── widgets/  # Reusable widgets
│   │   ├── services/ # API services
│   │   └── providers/# State management
│   └── Dockerfile
└── docker-compose.yml
```

## Prerequisites

- Docker and Docker Compose
- Node.js 18+ (for local development)
- Flutter SDK 3.0+ (for local development)

## Quick Start with Docker

1. **Clone and navigate to the project**:
   ```bash
   cd "ASI dashboard"
   ```

2. **Start all services**:
   ```bash
   docker-compose up -d
   ```

3. **Access the application**:
   - Frontend (Web): http://localhost:8080
   - Backend API: http://localhost:3000
   - API Health Check: http://localhost:3000/health

4. **View logs**:
   ```bash
   docker-compose logs -f
   ```

5. **Stop services**:
   ```bash
   docker-compose down
   ```

## Local Development

### Backend Setup

1. **Navigate to backend directory**:
   ```bash
   cd backend
   ```

2. **Install dependencies**:
   ```bash
   npm install
   ```

3. **Set up environment variables**:
   ```bash
   cp .env.example .env
   # Edit .env with your configuration
   ```

4. **Run database migrations**:
   ```bash
   # Make sure PostgreSQL is running
   psql -U asi_user -d asi_dashboard -f migrations/001_initial_schema.sql
   ```

5. **Start development server**:
   ```bash
   npm run dev
   ```

### Frontend Setup

1. **Navigate to frontend directory**:
   ```bash
   cd frontend
   ```

2. **Get Flutter dependencies**:
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

4. **Build for production**:
   ```bash
   # Web
   flutter build web
   
   # iOS
   flutter build ios
   
   # Android
   flutter build apk
   ```

## API Endpoints

### Health Check
- `GET /health` - Check API status

### Authentication
- `POST /api/auth/register` - Register new user
- `POST /api/auth/login` - Login and get JWT token
- `GET /api/auth/me` - Get current user profile (requires auth)
- `GET /api/auth/users` - Get all users (admin only)

### Chips
- `GET /api/chips` - Get all chips
- `GET /api/chips/:id` - Get chip by ID
- `POST /api/chips` - Create new chip
- `PUT /api/chips/:id` - Update chip
- `DELETE /api/chips/:id` - Delete chip

### Designs
- `GET /api/designs` - Get all designs
- `GET /api/designs/:id` - Get design by ID
- `GET /api/designs/chip/:chipId` - Get designs by chip ID
- `POST /api/designs` - Create new design
- `PUT /api/designs/:id` - Update design
- `DELETE /api/designs/:id` - Delete design

### Dashboard
- `GET /api/dashboard/stats` - Get dashboard statistics

See `backend/README_AUTH.md` for detailed authentication documentation.

## Database Schema

### Database Configuration
- **Database Name**: ASI
- **Username**: postgres
- **Password**: root
- **Port**: 5432

### User Roles
The system supports 5 user roles:
- **admin** - Full system access
- **project_manager** - Can manage projects, chips, and designs
- **lead** - Can view and edit chips and designs
- **engineer** - Can view and create chips and designs
- **customer** - Read-only access

### Users Table
- `id` (SERIAL PRIMARY KEY)
- `username` (VARCHAR, UNIQUE)
- `email` (VARCHAR, UNIQUE)
- `password_hash` (VARCHAR)
- `full_name` (VARCHAR)
- `role` (ENUM: admin, project_manager, lead, engineer, customer)
- `is_active` (BOOLEAN)
- `created_at` (TIMESTAMP)
- `updated_at` (TIMESTAMP)
- `last_login` (TIMESTAMP)

### Chips Table
- `id` (SERIAL PRIMARY KEY)
- `name` (VARCHAR)
- `description` (TEXT)
- `architecture` (VARCHAR)
- `process_node` (VARCHAR)
- `status` (VARCHAR)
- `created_by` (INTEGER, FOREIGN KEY to users)
- `updated_by` (INTEGER, FOREIGN KEY to users)
- `created_at` (TIMESTAMP)
- `updated_at` (TIMESTAMP)

### Designs Table
- `id` (SERIAL PRIMARY KEY)
- `chip_id` (INTEGER, FOREIGN KEY)
- `name` (VARCHAR)
- `description` (TEXT)
- `design_type` (VARCHAR)
- `status` (VARCHAR)
- `metadata` (JSONB)
- `created_by` (INTEGER, FOREIGN KEY to users)
- `updated_by` (INTEGER, FOREIGN KEY to users)
- `created_at` (TIMESTAMP)
- `updated_at` (TIMESTAMP)

### Default Users
Default users are created with password `password123`:
- admin / admin@asi.com (admin role)
- pm1 / pm1@asi.com (project_manager role)
- lead1 / lead1@asi.com (lead role)
- engineer1 / engineer1@asi.com (engineer role)
- customer1 / customer1@asi.com (customer role)

⚠️ **Change these passwords in production!**

## Environment Variables

### Backend (.env)
```
PORT=3000
NODE_ENV=development
DATABASE_URL=postgresql://postgres:root@postgres:5432/ASI
JWT_SECRET=your-secret-key-change-in-production
JWT_EXPIRES_IN=7d
```

## Troubleshooting

1. **Database connection issues**: Ensure PostgreSQL container is healthy before starting backend
2. **CORS errors**: Check that backend CORS is configured correctly
3. **Port conflicts**: Modify ports in docker-compose.yml if needed
4. **Flutter build issues**: Ensure Flutter SDK is properly installed and configured

## License

ISC

