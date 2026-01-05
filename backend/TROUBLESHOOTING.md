# Troubleshooting Database Connection

## Error: Password authentication failed

This error occurs when:
1. Docker PostgreSQL container is not running
2. Local PostgreSQL instance has different password
3. Wrong credentials in `.env` file

## Solutions

### Option 1: Start Docker PostgreSQL (Recommended)

1. **Start Docker Desktop**
   - Make sure Docker Desktop is running

2. **Start PostgreSQL container:**
   ```bash
   docker compose up -d postgres
   ```

3. **Verify it's running:**
   ```bash
   docker compose ps postgres
   ```

4. **Use these credentials in `.env`:**
   ```
   DATABASE_URL=postgresql://postgres:root@localhost:5432/ASI
   ```

### Option 2: Use Local PostgreSQL

If you have PostgreSQL installed locally:

1. **Check if PostgreSQL is running:**
   ```bash
   # Windows
   Get-Service -Name postgresql*
   ```

2. **Update `.env` with your local PostgreSQL credentials:**
   ```
   DATABASE_URL=postgresql://YOUR_USERNAME:YOUR_PASSWORD@localhost:5432/ASI
   ```

3. **Create the database if it doesn't exist:**
   ```sql
   CREATE DATABASE ASI;
   ```

4. **Run migrations:**
   ```bash
   psql -U YOUR_USERNAME -d ASI -f migrations/001_initial_schema.sql
   psql -U YOUR_USERNAME -d ASI -f migrations/002_users_and_roles.sql
   psql -U YOUR_USERNAME -d ASI -f migrations/003_add_admin_user.sql
   ```

### Option 3: Check PostgreSQL Container Status

If Docker is running but container isn't:

```bash
# Check all containers
docker ps -a

# Start the container
docker start asi_postgres

# Or recreate it
docker compose up -d postgres
```

## Verify Connection

Test the connection:
```bash
# Using psql (if available)
psql -U postgres -h localhost -d ASI

# Or using Docker
docker exec -it asi_postgres psql -U postgres -d ASI
```

## Common Issues

### Port 5432 already in use
- Another PostgreSQL instance is running
- Stop it or change the port in docker-compose.yml

### Connection refused
- PostgreSQL is not running
- Start Docker Desktop and the container

### Wrong password
- Check docker-compose.yml for the correct password
- Default is `root` for this project












