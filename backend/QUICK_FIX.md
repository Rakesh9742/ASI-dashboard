# Quick Fix for Password Authentication Error

## Problem
Local PostgreSQL 17 is running, but password "root" doesn't work.

## Fastest Solution

### Option 1: Set PostgreSQL Password to "root" (Recommended)

1. **Open PowerShell as Administrator**

2. **Connect to PostgreSQL:**
   ```powershell
   psql -U postgres
   ```
   (If it asks for password, try: empty, "postgres", or your Windows password)

3. **Set the password:**
   ```sql
   ALTER USER postgres WITH PASSWORD 'root';
   \q
   ```

4. **Your `.env` file will now work:**
   ```
   DATABASE_URL=postgresql://postgres:root@localhost:5432/ASI
   ```

### Option 2: Use Empty Password (Temporary)

If you can't set the password, temporarily use empty password:

1. **Update `.env`:**
   ```
   DATABASE_URL=postgresql://postgres@localhost:5432/ASI
   ```
   (No password in the URL)

2. **Then set password later using Option 1**

### Option 3: Create Database and Run Migrations

After setting password, create the database:

```powershell
# Create database
psql -U postgres -c "CREATE DATABASE ASI;"

# Run migrations
cd backend
psql -U postgres -d ASI -f migrations/001_initial_schema.sql
psql -U postgres -d ASI -f migrations/002_users_and_roles.sql
psql -U postgres -d ASI -f migrations/003_add_admin_user.sql
```

### Option 4: Stop Local PostgreSQL, Use Docker

If you prefer Docker:

```powershell
# Stop local PostgreSQL
Stop-Service postgresql-x64-17

# Start Docker PostgreSQL (wait for Docker Desktop to be ready)
docker compose up -d postgres

# Use Docker credentials (already in .env)
```

## Test Connection

After setting password, test:
```powershell
psql -U postgres -h localhost -d ASI
# Enter password: root
```

If it connects, your backend will work!




