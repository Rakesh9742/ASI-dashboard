# Setup Local PostgreSQL Connection

## Current Situation
- Local PostgreSQL 17 service is running
- Docker PostgreSQL is not accessible
- Need to configure connection to local PostgreSQL

## Solution: Configure Local PostgreSQL

### Step 1: Find or Set PostgreSQL Password

**Option A: Try common passwords**
- Empty password (just press Enter)
- `postgres`
- Your Windows username

**Option B: Reset PostgreSQL password**

1. **Edit PostgreSQL config to allow local connections without password:**
   - Find `pg_hba.conf` (usually in `C:\Program Files\PostgreSQL\17\data\`)
   - Change authentication method to `trust` for local connections:
     ```
     host    all             all             127.0.0.1/32            trust
     ```
   - Restart PostgreSQL service:
     ```powershell
     Restart-Service postgresql-x64-17
     ```

2. **Connect and set password:**
   ```sql
   psql -U postgres
   ALTER USER postgres WITH PASSWORD 'root';
   ```

3. **Revert pg_hba.conf back to md5:**
   ```
   host    all             all             127.0.0.1/32            md5
   ```
   - Restart service again

### Step 2: Create ASI Database

```sql
psql -U postgres
CREATE DATABASE ASI;
\q
```

### Step 3: Run Migrations

```bash
cd backend
psql -U postgres -d ASI -f migrations/001_initial_schema.sql
psql -U postgres -d ASI -f migrations/002_users_and_roles.sql
psql -U postgres -d ASI -f migrations/003_add_admin_user.sql
```

### Step 4: Update .env File

Once you know the password, update `backend/.env`:
```
DATABASE_URL=postgresql://postgres:YOUR_PASSWORD@localhost:5432/ASI
```

## Quick Fix: Use Trust Authentication Temporarily

1. **Edit `pg_hba.conf`:**
   ```
   # Find this file:
   C:\Program Files\PostgreSQL\17\data\pg_hba.conf
   
   # Change this line:
   host    all             all             127.0.0.1/32            md5
   
   # To:
   host    all             all             127.0.0.1/32            trust
   ```

2. **Restart PostgreSQL:**
   ```powershell
   Restart-Service postgresql-x64-17
   ```

3. **Update .env (no password needed):**
   ```
   DATABASE_URL=postgresql://postgres@localhost:5432/ASI
   ```

4. **Set password later:**
   ```sql
   psql -U postgres
   ALTER USER postgres WITH PASSWORD 'root';
   ```

5. **Change pg_hba.conf back to md5 and restart**

## Alternative: Stop Local PostgreSQL and Use Docker

If you prefer Docker:

1. **Stop local PostgreSQL:**
   ```powershell
   Stop-Service postgresql-x64-17
   ```

2. **Start Docker PostgreSQL:**
   ```bash
   docker compose up -d postgres
   ```

3. **Use Docker credentials:**
   ```
   DATABASE_URL=postgresql://postgres:root@localhost:5432/ASI
   ```












