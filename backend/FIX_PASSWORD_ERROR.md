# Fix Password Authentication Error

## Current Situation
- Port 5432 is open (PostgreSQL is running)
- Password authentication is failing
- This could be a local PostgreSQL instance with different credentials

## Solution Options

### Option 1: Wait for Docker Desktop to Fully Start

Docker Desktop might still be starting. Wait 1-2 minutes, then:

```bash
# Check if Docker is ready
docker ps

# Start PostgreSQL container
docker compose up -d postgres

# Verify
docker compose ps postgres
```

### Option 2: Use Local PostgreSQL (If Installed)

If you have PostgreSQL installed locally, you need to:

1. **Find your PostgreSQL password:**
   - Check your PostgreSQL installation
   - Default might be empty or different

2. **Update `.env` file:**
   ```
   DATABASE_URL=postgresql://postgres:YOUR_LOCAL_PASSWORD@localhost:5432/ASI
   ```
   
   Or if your local user is different:
   ```
   DATABASE_URL=postgresql://YOUR_USERNAME:YOUR_PASSWORD@localhost:5432/ASI
   ```

3. **Create the database:**
   ```sql
   CREATE DATABASE ASI;
   ```

4. **Run migrations:**
   ```bash
   psql -U postgres -d ASI -f migrations/001_initial_schema.sql
   psql -U postgres -d ASI -f migrations/002_users_and_roles.sql
   psql -U postgres -d ASI -f migrations/003_add_admin_user.sql
   ```

### Option 3: Stop Local PostgreSQL and Use Docker

If you want to use Docker PostgreSQL:

1. **Stop local PostgreSQL service:**
   ```powershell
   Stop-Service postgresql*
   ```

2. **Wait for Docker Desktop to fully start**

3. **Start Docker PostgreSQL:**
   ```bash
   docker compose up -d postgres
   ```

4. **Use Docker credentials in `.env`:**
   ```
   DATABASE_URL=postgresql://postgres:root@localhost:5432/ASI
   ```

## Quick Test

Test the connection manually:

```bash
# Try connecting with psql
psql -U postgres -h localhost -d ASI

# If it asks for password, try:
# - Empty password (just press Enter)
# - "root" (Docker password)
# - Your local PostgreSQL password
```

## Recommended Action

1. **Wait 2-3 minutes for Docker Desktop to fully initialize**
2. **Then run:**
   ```bash
   docker compose up -d postgres
   docker compose ps postgres
   ```
3. **If Docker still doesn't work, check which PostgreSQL is running:**
   ```powershell
   Get-Service | Where-Object {$_.Name -like "*postgres*"}
   ```
















