# Manual Password Reset (If Script Doesn't Work)

## Method 1: Using pg_hba.conf (Recommended)

### Step 1: Find pg_hba.conf
Location: `C:\Program Files\PostgreSQL\17\data\pg_hba.conf`

### Step 2: Edit as Administrator
1. Right-click the file → Properties → Security → Edit
2. Give yourself Full Control (temporarily)
3. Or run Notepad as Administrator and open the file

### Step 3: Modify Authentication
Find these lines:
```
host    all             all             127.0.0.1/32            md5
host    all             all             ::1/128                 md5
```

Change `md5` to `trust`:
```
host    all             all             127.0.0.1/32            trust
host    all             all             ::1/128                 trust
```

### Step 4: Restart PostgreSQL
```powershell
Restart-Service postgresql-x64-17
```

### Step 5: Connect and Set Password
```powershell
psql -U postgres
```

Then in psql:
```sql
ALTER USER postgres WITH PASSWORD 'root';
\q
```

### Step 6: Restore pg_hba.conf
Change `trust` back to `md5` and restart service again.

---

## Method 2: Using Windows Authentication

If PostgreSQL supports Windows auth:

```powershell
# Connect as Windows user
psql -U $env:USERNAME -d postgres

# Then set postgres user password
ALTER USER postgres WITH PASSWORD 'root';
```

---

## Method 3: Reinstall PostgreSQL (Last Resort)

If nothing works, you can reinstall PostgreSQL and set password during installation.

---

## After Setting Password

1. **Test connection:**
   ```powershell
   $env:PGPASSWORD='root'
   psql -U postgres -c "SELECT version();"
   ```

2. **Create database:**
   ```powershell
   psql -U postgres -c "CREATE DATABASE ASI;"
   ```

3. **Run migrations:**
   ```powershell
   cd backend
   $env:PGPASSWORD='root'
   psql -U postgres -d ASI -f migrations/001_initial_schema.sql
   psql -U postgres -d ASI -f migrations/002_users_and_roles.sql
   psql -U postgres -d ASI -f migrations/003_add_admin_user.sql
   ```

4. **Restart backend server**









