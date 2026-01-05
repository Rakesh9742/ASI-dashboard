# EC2 PostgreSQL Database Setup Guide

This guide will help you set up the ASI Dashboard database on your EC2 server.

## Prerequisites

1. **PostgreSQL installed on EC2**
   ```bash
   # Ubuntu/Debian
   sudo apt update
   sudo apt install postgresql postgresql-contrib
   
   # Amazon Linux
   sudo yum install postgresql15-server postgresql15
   ```

2. **PostgreSQL service running**
   ```bash
   sudo systemctl start postgresql
   sudo systemctl enable postgresql
   ```

## Step 1: Connect to PostgreSQL

```bash
# Switch to postgres user
sudo -u postgres psql

# Or if you have a postgres user with password
psql -U postgres -h localhost
```

## Step 2: Create Database

```sql
-- Create the database
CREATE DATABASE ASI;

-- Connect to the database
\c ASI
```

## Step 3: Run the Complete Schema

### Option A: Using psql command line

```bash
# From your local machine (if you have the file)
psql -U postgres -h YOUR_EC2_IP -d ASI -f complete_schema.sql

# Or from EC2 server
sudo -u postgres psql -d ASI -f /path/to/complete_schema.sql
```

### Option B: Copy and paste

1. Copy the contents of `complete_schema.sql`
2. Connect to PostgreSQL:
   ```bash
   sudo -u postgres psql -d ASI
   ```
3. Paste the entire SQL content
4. Press Enter to execute

### Option C: Using SSH and psql

```bash
# From your local machine
scp backend/migrations/complete_schema.sql ec2-user@YOUR_EC2_IP:/tmp/
ssh ec2-user@YOUR_EC2_IP
sudo -u postgres psql -d ASI -f /tmp/complete_schema.sql
```

## Step 4: Verify Installation

```sql
-- Connect to database
\c ASI

-- List all tables
\dt

-- Check if admin user exists
SELECT username, email, role FROM users WHERE username = 'admin1';

-- Check if domains were created
SELECT * FROM domains;

-- Check table count
SELECT 
    schemaname,
    tablename
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY tablename;
```

Expected tables:
- chips
- designs
- domains
- project_domains
- projects
- users
- zoho_projects_mapping
- zoho_tokens

## Step 5: Configure PostgreSQL for Remote Access (Optional)

If your backend will connect from outside EC2:

1. **Edit postgresql.conf**
   ```bash
   sudo nano /etc/postgresql/15/main/postgresql.conf
   # or
   sudo nano /var/lib/pgsql/15/data/postgresql.conf
   ```
   
   Find and uncomment:
   ```conf
   listen_addresses = '*'
   ```

2. **Edit pg_hba.conf**
   ```bash
   sudo nano /etc/postgresql/15/main/pg_hba.conf
   # or
   sudo nano /var/lib/pgsql/15/data/pg_hba.conf
   ```
   
   Add line for your network:
   ```
   host    all             all             0.0.0.0/0               md5
   ```

3. **Restart PostgreSQL**
   ```bash
   sudo systemctl restart postgresql
   ```

4. **Set password for postgres user**
   ```sql
   ALTER USER postgres WITH PASSWORD 'your_secure_password';
   ```

## Step 6: Update Backend Configuration

Update your backend `.env` or environment variables:

```env
DATABASE_URL=postgresql://postgres:your_password@YOUR_EC2_IP:5432/ASI
```

Or if connecting locally on EC2:
```env
DATABASE_URL=postgresql://postgres:your_password@localhost:5432/ASI
```

## Default Admin Credentials

After running the schema, you can login with:

- **Username:** `admin1`
- **Email:** `admin@1.com`
- **Password:** `test@1234`

⚠️ **IMPORTANT:** Change this password immediately after first login!

## Troubleshooting

### Connection Refused
- Check if PostgreSQL is running: `sudo systemctl status postgresql`
- Check firewall: `sudo ufw status` (allow port 5432)
- Verify PostgreSQL is listening: `sudo netstat -tlnp | grep 5432`

### Permission Denied
- Make sure you're using the correct user: `sudo -u postgres psql`
- Check file permissions if using -f option

### Database Already Exists
- Drop and recreate: `DROP DATABASE ASI; CREATE DATABASE ASI;`
- Or use `\c ASI` to connect to existing database

### Schema Errors
- Make sure you're running the complete file, not individual migrations
- Check PostgreSQL version (should be 12+)
- Verify all SQL statements executed successfully

## Security Best Practices

1. **Change default passwords**
   ```sql
   ALTER USER postgres WITH PASSWORD 'strong_password_here';
   ```

2. **Create application-specific user**
   ```sql
   CREATE USER asi_app WITH PASSWORD 'app_password';
   GRANT ALL PRIVILEGES ON DATABASE ASI TO asi_app;
   GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO asi_app;
   GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO asi_app;
   ```

3. **Restrict network access** - Only allow connections from your application servers

4. **Use SSL/TLS** for remote connections

5. **Regular backups**
   ```bash
   # Create backup
   sudo -u postgres pg_dump ASI > backup_$(date +%Y%m%d).sql
   
   # Restore backup
   sudo -u postgres psql -d ASI < backup_20231224.sql
   ```

## Next Steps

After setting up the database:

1. Update your backend configuration with the database connection string
2. Test the connection from your backend application
3. Run any additional migrations if needed
4. Set up database backups
5. Configure monitoring and alerts


