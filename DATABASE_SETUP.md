# Database Setup Guide

## Database Configuration

- **Database Name**: ASI
- **Username**: postgres
- **Password**: root
- **Host**: postgres (in Docker) / localhost (local)
- **Port**: 5432

## User Roles

The system includes 5 predefined roles:

1. **admin** - Full system access
   - Can manage all users
   - Can create, edit, and delete all chips and designs
   - Access to all dashboard features

2. **project_manager** - Project management
   - Can manage projects, chips, and designs
   - Can assign tasks to engineers
   - View project statistics

3. **lead** - Lead engineer
   - Can view and edit chips and designs
   - Can assign work to engineers
   - Review and approve designs

4. **engineer** - Engineer
   - Can view and create chips and designs
   - Can update assigned designs
   - Limited editing permissions

5. **customer** - Customer
   - Read-only access to assigned projects
   - Can view chip and design status
   - Cannot modify data

## Default Users

The following users are automatically created when the database is initialized:

| Username | Email | Role | Password |
|----------|-------|------|----------|
| admin | admin@asi.com | admin | password123 |
| pm1 | pm1@asi.com | project_manager | password123 |
| lead1 | lead1@asi.com | lead | password123 |
| engineer1 | engineer1@asi.com | engineer | password123 |
| customer1 | customer1@asi.com | customer | password123 |

⚠️ **SECURITY WARNING**: These are default credentials. **Change all passwords immediately in production!**

## Database Initialization

The database is automatically initialized when you start Docker Compose:

```bash
docker-compose up -d
```

The initialization scripts run in this order:
1. `001_initial_schema.sql` - Creates chips and designs tables
2. `002_users_and_roles.sql` - Creates users table, roles, and default users

## Manual Database Setup

If you need to set up the database manually:

1. **Connect to PostgreSQL**:
   ```bash
   psql -U postgres -d ASI
   ```

2. **Run migrations**:
   ```sql
   \i backend/migrations/001_initial_schema.sql
   \i backend/migrations/002_users_and_roles.sql
   ```

## Creating New Users

### Via API

```bash
POST /api/auth/register
Content-Type: application/json

{
  "username": "newuser",
  "email": "user@example.com",
  "password": "securepassword",
  "full_name": "Full Name",
  "role": "engineer"
}
```

### Via SQL

```sql
INSERT INTO users (username, email, password_hash, full_name, role)
VALUES (
  'newuser',
  'user@example.com',
  '$2a$10$...', -- bcrypt hash of password
  'Full Name',
  'engineer'
);
```

To generate a password hash, use the backend script:
```bash
cd backend
npm install
node -e "const bcrypt = require('bcryptjs'); bcrypt.hash('yourpassword', 10).then(hash => console.log(hash));"
```

## Database Schema

### Users Table
- Tracks all system users
- Stores authentication credentials
- Links to chips and designs via created_by/updated_by

### Chips Table
- Stores chip design information
- Links to users who created/updated records
- Status tracking (design, testing, production)

### Designs Table
- Stores individual design components
- Links to parent chips
- Stores metadata as JSONB
- Tracks creation and updates by users

## Role Permissions Matrix

| Action | Admin | PM | Lead | Engineer | Customer |
|--------|-------|----|----|----------|----------|
| View all chips | ✅ | ✅ | ✅ | ✅ | ✅* |
| Create chips | ✅ | ✅ | ✅ | ✅ | ❌ |
| Edit any chip | ✅ | ✅ | ✅ | ❌ | ❌ |
| Delete chips | ✅ | ✅ | ❌ | ❌ | ❌ |
| View all designs | ✅ | ✅ | ✅ | ✅ | ✅* |
| Create designs | ✅ | ✅ | ✅ | ✅ | ❌ |
| Edit any design | ✅ | ✅ | ✅ | ❌ | ❌ |
| Delete designs | ✅ | ✅ | ❌ | ❌ | ❌ |
| Manage users | ✅ | ❌ | ❌ | ❌ | ❌ |
| View dashboard | ✅ | ✅ | ✅ | ✅ | ✅* |

*Customers can only view assigned projects (to be implemented)

## Backup and Restore

### Backup
```bash
docker exec asi_postgres pg_dump -U postgres ASI > backup.sql
```

### Restore
```bash
docker exec -i asi_postgres psql -U postgres ASI < backup.sql
```

## Troubleshooting

### Database Connection Issues

1. Check if PostgreSQL is running:
   ```bash
   docker-compose ps postgres
   ```

2. Check logs:
   ```bash
   docker-compose logs postgres
   ```

3. Verify connection string in `.env`:
   ```
   DATABASE_URL=postgresql://postgres:root@postgres:5432/ASI
   ```

### Migration Issues

If migrations fail:
1. Stop containers: `docker-compose down -v`
2. Remove volumes: `docker volume rm asi_dashboard_postgres_data`
3. Restart: `docker-compose up -d`

### Password Reset

To reset a user's password:

```sql
UPDATE users 
SET password_hash = '$2a$10$...' -- new bcrypt hash
WHERE username = 'admin';
```

Generate new hash using the method described in "Creating New Users" section.








