# EC2 Deployment Guide - ASI Dashboard QMS Flow

This guide provides step-by-step instructions for deploying the ASI Dashboard (including QMS flow) on an EC2 instance.

## Prerequisites

1. **EC2 Instance** running Ubuntu 22.04 or Amazon Linux 2023
2. **SSH Access** to EC2 instance
3. **Git** installed on EC2
4. **Domain Name** (optional, for production)
5. **Security Groups** configured:
   - Port 22 (SSH)
   - Port 80 (HTTP)
   - Port 443 (HTTPS)
   - Port 3000 (Backend - optional, if accessing directly)
   - Port 8080 (Frontend - optional, if accessing directly)
   - Port 5432 (PostgreSQL - restrict to internal/backend only)

## Step 1: EC2 Instance Setup

### 1.1 Connect to EC2 Instance

```bash
ssh -i your-key.pem ubuntu@YOUR_EC2_IP
# or
ssh -i your-key.pem ec2-user@YOUR_EC2_IP
```

### 1.2 Update System Packages

```bash
# Ubuntu/Debian
sudo apt update && sudo apt upgrade -y

# Amazon Linux
sudo yum update -y
```

### 1.3 Install Required Software

```bash
# Ubuntu/Debian
sudo apt install -y git curl wget build-essential

# Amazon Linux
sudo yum install -y git curl wget gcc gcc-c++ make
```

### 1.4 Install Docker and Docker Compose

```bash
# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

# Install Docker Compose V2
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Verify installation
docker --version
docker-compose --version

# Log out and log back in for group changes to take effect
exit
# SSH back in
```

### 1.5 Install PostgreSQL Client (for migrations)

```bash
# Ubuntu/Debian
sudo apt install -y postgresql-client

# Amazon Linux
sudo yum install -y postgresql15
```

## Step 2: Database Setup

### 2.1 Install and Configure PostgreSQL

```bash
# Ubuntu/Debian
sudo apt install -y postgresql postgresql-contrib

# Amazon Linux
sudo yum install -y postgresql15-server postgresql15
sudo /usr/pgsql-15/bin/postgresql-15-setup initdb
```

### 2.2 Start PostgreSQL Service

```bash
sudo systemctl start postgresql
sudo systemctl enable postgresql
```

### 2.3 Create Database and User

```bash
# Switch to postgres user
sudo -u postgres psql

# Inside psql, run:
CREATE DATABASE ASI;
CREATE USER asi_user WITH PASSWORD 'your_secure_password_here';
GRANT ALL PRIVILEGES ON DATABASE ASI TO asi_user;
ALTER DATABASE ASI OWNER TO asi_user;
\q
```

### 2.4 Configure PostgreSQL for Application Access

```bash
# Edit pg_hba.conf
sudo nano /etc/postgresql/15/main/pg_hba.conf
# or for Amazon Linux
sudo nano /var/lib/pgsql/15/data/pg_hba.conf

# Add this line for local connections:
local   all             all                                     md5
host    all             all             127.0.0.1/32            md5

# For remote access (if needed):
host    all             all             0.0.0.0/0               md5

# Restart PostgreSQL
sudo systemctl restart postgresql
```

## Step 3: Clone and Setup Application

### 3.1 Clone Repository

```bash
cd /opt
sudo mkdir -p asi-dashboard
sudo chown $USER:$USER asi-dashboard
cd asi-dashboard
git clone https://your-repo-url.git .
# or
git clone https://your-repo-url.git ASI-dashboard
cd ASI-dashboard
```

### 3.2 Run Database Migrations

**IMPORTANT**: Run migrations in order to create QMS tables on staging database.

```bash
# Navigate to migrations directory
cd backend/migrations

# Connect to database
sudo -u postgres psql -d ASI

# Or with password:
PGPASSWORD=your_secure_password_here psql -U asi_user -d ASI -h localhost
```

**Run migrations in order:**

```sql
-- 1. Base schema (if not already run)
\i 001_initial_schema.sql
\i 002_users_and_roles.sql
\i 003_add_admin_user.sql
\i 004_domains_table.sql
\i 005_add_domain_to_users.sql
\i 006_create_projects.sql
\i 007_create_zoho_integration.sql
\i 010_create_physical_design_schema.sql
\i 011_convert_pd_fields_to_varchar.sql

-- 2. QMS Schema (REQUIRED for QMS flow)
\i 012_create_qms_schema.sql

-- 3. QMS Additions
\i 013_add_check_item_details.sql
\i 014_add_version_to_check_items.sql
\i 015_ensure_qms_columns_exist.sql
\i 016_add_checklist_submission_tracking.sql
\i 017_fix_qms_audit_log_foreign_keys.sql

-- Verify tables were created
\dt
\q
```

**Alternative: Run migrations from command line**

```bash
# From project root
cd /opt/asi-dashboard/ASI-dashboard

# Run each migration file
sudo -u postgres psql -d ASI -f backend/migrations/012_create_qms_schema.sql
sudo -u postgres psql -d ASI -f backend/migrations/013_add_check_item_details.sql
sudo -u postgres psql -d ASI -f backend/migrations/014_add_version_to_check_items.sql
sudo -u postgres psql -d ASI -f backend/migrations/015_ensure_qms_columns_exist.sql
sudo -u postgres psql -d ASI -f backend/migrations/016_add_checklist_submission_tracking.sql
sudo -u postgres psql -d ASI -f backend/migrations/017_fix_qms_audit_log_foreign_keys.sql

# Verify QMS tables exist
sudo -u postgres psql -d ASI -c "\dt checklists"
sudo -u postgres psql -d ASI -c "\dt check_items"
sudo -u postgres psql -d ASI -c "\dt c_report_data"
```

**Verify QMS Tables:**

```sql
-- Check if tables exist
SELECT table_name 
FROM information_schema.tables 
WHERE table_schema = 'public' 
  AND table_name IN (
    'checklists', 
    'check_items', 
    'c_report_data', 
    'check_item_approvals', 
    'qms_audit_log'
  )
ORDER BY table_name;

-- Should return 5 tables
```

## Step 4: Configure Environment Variables

### 4.1 Backend Environment Variables

```bash
cd /opt/asi-dashboard/ASI-dashboard/backend
nano .env
```

Create `.env` file with:

```env
# Server Configuration
PORT=3000
NODE_ENV=production

# Database Configuration
DATABASE_URL=postgresql://asi_user:your_secure_password_here@localhost:5432/ASI

# JWT Configuration
JWT_SECRET=your_very_secure_jwt_secret_key_here_change_this
JWT_EXPIRES_IN=7d

# Application URLs
BACKEND_URL=http://YOUR_EC2_IP:3000
FRONTEND_URL=http://YOUR_EC2_IP:8080

# CORS Configuration (if needed)
CORS_ORIGIN=http://YOUR_EC2_IP:8080,http://YOUR_DOMAIN.com
```

### 4.2 Frontend Environment Variables

```bash
cd /opt/asi-dashboard/ASI-dashboard/frontend
nano .env
```

Create `.env` file with (if needed - usually not required as frontend uses relative URLs):

```env
BACKEND_URL=http://YOUR_EC2_IP:3000
```

## Step 5: Update Docker Compose for Production

### 5.1 Update docker-compose.yml

```bash
cd /opt/asi-dashboard/ASI-dashboard
nano docker-compose.yml
```

Update the docker-compose.yml to use your database credentials and production settings:

```yaml
services:
  postgres:
    image: postgres:15-alpine
    container_name: asi_postgres
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: root
      POSTGRES_DB: ASI
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - asi_network
    restart: unless-stopped

  backend:
    build:
      context: ./backend
      dockerfile: Dockerfile
    container_name: asi_backend
    environment:
      PORT: 3000
      NODE_ENV: production
      DATABASE_URL: postgresql://postgres:root@postgres:5432/ASI
      JWT_SECRET: ${JWT_SECRET:-your-secret-key-change-in-production}
      JWT_EXPIRES_IN: 7d
      BACKEND_URL: ${BACKEND_URL:-http://localhost:3000}
      FRONTEND_URL: ${FRONTEND_URL:-http://localhost:8080}
    ports:
      - "3000:3000"
    depends_on:
      postgres:
        condition: service_healthy
    volumes:
      - ./backend:/app
      - /app/node_modules
    networks:
      - asi_network
    restart: unless-stopped
    command: npm start

  frontend:
    build:
      context: ./frontend
      dockerfile: Dockerfile
    container_name: asi_frontend
    ports:
      - "8080:8080"
    depends_on:
      - backend
    environment:
      - BACKEND_URL=${BACKEND_URL:-http://backend:3000}
      - FRONTEND_URL=${FRONTEND_URL:-http://localhost:8080}
    networks:
      - asi_network
    restart: unless-stopped

volumes:
  postgres_data:

networks:
  asi_network:
    driver: bridge
```

**Note**: For production, you may want to:
- Use external PostgreSQL database (not Docker)
- Use environment-specific secrets
- Configure SSL/TLS
- Set up reverse proxy (Nginx)

## Step 6: Build and Start Application

### 6.1 Build Docker Images

```bash
cd /opt/asi-dashboard/ASI-dashboard

# Build all services
docker-compose build

# Or build individually
docker-compose build backend
docker-compose build frontend
```

### 6.2 Start Services

```bash
# Start all services in detached mode
docker-compose up -d

# View logs
docker-compose logs -f

# Check service status
docker-compose ps
```

### 6.3 Verify Services are Running

```bash
# Check if containers are running
docker ps

# Check backend health
curl http://localhost:3000/health
# or
curl http://YOUR_EC2_IP:3000/health

# Check frontend
curl http://localhost:8080
# or
curl http://YOUR_EC2_IP:8080
```

## Step 7: Configure Nginx Reverse Proxy (Recommended for Production)

### 7.1 Install Nginx

```bash
sudo apt install -y nginx
# or
sudo yum install -y nginx
```

### 7.2 Create Nginx Configuration

```bash
sudo nano /etc/nginx/sites-available/asi-dashboard
```

Add configuration:

```nginx
upstream backend {
    server localhost:3000;
}

upstream frontend {
    server localhost:8080;
}

server {
    listen 80;
    server_name YOUR_DOMAIN.com YOUR_EC2_IP;

    # Frontend
    location / {
        proxy_pass http://frontend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # Backend API
    location /api {
        proxy_pass http://backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # CORS headers (if needed)
        add_header 'Access-Control-Allow-Origin' '*' always;
        add_header 'Access-Control-Allow-Methods' 'GET, POST, PUT, DELETE, OPTIONS' always;
        add_header 'Access-Control-Allow-Headers' 'Authorization, Content-Type' always;
    }
}
```

### 7.3 Enable Site and Start Nginx

```bash
# Create symlink (Ubuntu/Debian)
sudo ln -s /etc/nginx/sites-available/asi-dashboard /etc/nginx/sites-enabled/

# Test configuration
sudo nginx -t

# Start/restart Nginx
sudo systemctl start nginx
sudo systemctl enable nginx
sudo systemctl restart nginx
```

## Step 8: Setup SSL with Let's Encrypt (Optional but Recommended)

```bash
# Install Certbot
sudo apt install -y certbot python3-certbot-nginx
# or
sudo yum install -y certbot python3-certbot-nginx

# Obtain SSL certificate
sudo certbot --nginx -d YOUR_DOMAIN.com

# Auto-renewal is set up automatically
```

## Step 9: Firewall Configuration

```bash
# Ubuntu/Debian - UFW
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable

# Amazon Linux - Firewalld
sudo firewall-cmd --permanent --add-service=ssh
sudo firewall-cmd --permanent --add-service=http
sudo firewall-cmd --permanent --add-service=https
sudo firewall-cmd --reload
```

## Step 10: Application Management Commands

### 10.1 Docker Compose Commands

```bash
# Start services
docker-compose up -d

# Stop services
docker-compose down

# Restart services
docker-compose restart

# View logs
docker-compose logs -f backend
docker-compose logs -f frontend
docker-compose logs -f postgres

# Rebuild and restart
docker-compose up -d --build

# Stop and remove everything (including volumes)
docker-compose down -v
```

### 10.2 Database Management

```bash
# Connect to database
sudo -u postgres psql -d ASI

# Backup database
sudo -u postgres pg_dump ASI > backup_$(date +%Y%m%d_%H%M%S).sql

# Restore database
sudo -u postgres psql -d ASI < backup_YYYYMMDD_HHMMSS.sql

# Run additional migrations
sudo -u postgres psql -d ASI -f backend/migrations/XXX_migration_name.sql
```

### 10.3 Service Status Checks

```bash
# Check Docker containers
docker ps

# Check Docker logs
docker logs asi_backend
docker logs asi_frontend
docker logs asi_postgres

# Check system resources
docker stats

# Check PostgreSQL status
sudo systemctl status postgresql

# Check Nginx status
sudo systemctl status nginx
```

## Step 11: Verify QMS Deployment

### 11.1 Access Application

```bash
# Open in browser
http://YOUR_EC2_IP:8080
# or
http://YOUR_DOMAIN.com
```

### 11.2 Verify QMS Tables

```bash
# Connect to database
sudo -u postgres psql -d ASI

# Check QMS tables
SELECT COUNT(*) FROM checklists;
SELECT COUNT(*) FROM check_items;
SELECT COUNT(*) FROM c_report_data;
SELECT COUNT(*) FROM check_item_approvals;
SELECT COUNT(*) FROM qms_audit_log;

# Check table structure
\d checklists
\d check_items
\d c_report_data

\q
```

### 11.3 Test QMS Endpoints

```bash
# Get QMS filter options
curl http://YOUR_EC2_IP:3000/api/qms/filters

# Get checklists
curl -H "Authorization: Bearer YOUR_JWT_TOKEN" http://YOUR_EC2_IP:3000/api/qms/checklists
```

## Troubleshooting

### Database Connection Issues

```bash
# Check PostgreSQL is running
sudo systemctl status postgresql

# Check PostgreSQL logs
sudo tail -f /var/log/postgresql/postgresql-15-main.log

# Test connection
psql -U asi_user -h localhost -d ASI
```

### Backend Issues

```bash
# Check backend logs
docker logs asi_backend -f

# Restart backend
docker restart asi_backend

# Check environment variables
docker exec asi_backend env | grep DATABASE_URL
```

### Frontend Issues

```bash
# Check frontend logs
docker logs asi_frontend -f

# Restart frontend
docker restart asi_frontend
```

### Migration Issues

```bash
# Check if migration ran successfully
sudo -u postgres psql -d ASI -c "\dt" | grep -E "checklist|check_item"

# Re-run specific migration
sudo -u postgres psql -d ASI -f backend/migrations/012_create_qms_schema.sql
```

## Security Checklist

- [ ] Change default database passwords
- [ ] Use strong JWT_SECRET
- [ ] Configure firewall rules
- [ ] Enable SSL/HTTPS
- [ ] Restrict database access to localhost only
- [ ] Regular database backups
- [ ] Update system packages regularly
- [ ] Monitor application logs
- [ ] Set up log rotation
- [ ] Configure automated backups

## Backup Strategy

### Database Backup Script

Create `/opt/asi-dashboard/backup.sh`:

```bash
#!/bin/bash
BACKUP_DIR="/opt/asi-dashboard/backups"
DATE=$(date +%Y%m%d_%H%M%S)
mkdir -p $BACKUP_DIR
sudo -u postgres pg_dump ASI > $BACKUP_DIR/asi_backup_$DATE.sql
# Keep only last 7 days of backups
find $BACKUP_DIR -name "asi_backup_*.sql" -mtime +7 -delete
```

Make executable and add to crontab:

```bash
chmod +x /opt/asi-dashboard/backup.sh
crontab -e
# Add: 0 2 * * * /opt/asi-dashboard/backup.sh
```

## Monitoring

Consider setting up:
- **Application monitoring**: PM2, New Relic, DataDog
- **Log aggregation**: ELK Stack, CloudWatch
- **Uptime monitoring**: UptimeRobot, Pingdom
- **Database monitoring**: pgAdmin, Datadog PostgreSQL integration

## Summary

After completing these steps, you should have:
1. ✅ PostgreSQL database with QMS tables created
2. ✅ Backend API running on port 3000
3. ✅ Frontend application running on port 8080
4. ✅ Nginx reverse proxy configured (optional)
5. ✅ SSL certificate installed (optional)
6. ✅ Services configured to auto-start on reboot

Access your application at:
- Frontend: `http://YOUR_EC2_IP:8080` or `http://YOUR_DOMAIN.com`
- Backend API: `http://YOUR_EC2_IP:3000/api` or `http://YOUR_DOMAIN.com/api`

Default admin credentials (change immediately):
- Username: `admin1`
- Email: `admin@1.com`
- Password: `test@1234`
