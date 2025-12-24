# Environment Variables Setup for EC2

## Required Environment Variables

Update these in your `.env` file or set them as environment variables on your EC2 instance.

### Application URLs

```bash
# Backend URL - Your EC2 backend API URL
BACKEND_URL=http://YOUR_EC2_IP:3000
# Or with domain:
# BACKEND_URL=https://api.yourdomain.com

# Frontend URL - Your EC2 frontend URL  
FRONTEND_URL=http://YOUR_EC2_IP:8080
# Or with domain:
# FRONTEND_URL=https://yourdomain.com
```

### Database

```bash
# PostgreSQL connection string
DATABASE_URL=postgresql://postgres:YOUR_PASSWORD@localhost:5432/ASI
# Or if database is on different server:
# DATABASE_URL=postgresql://postgres:YOUR_PASSWORD@DB_SERVER_IP:5432/ASI
```

### Zoho Configuration

```bash
# Zoho OAuth credentials
ZOHO_CLIENT_ID=your_client_id
ZOHO_CLIENT_SECRET=your_client_secret

# Zoho Redirect URI - Will be auto-built from BACKEND_URL
# Or set manually:
# ZOHO_REDIRECT_URI=http://YOUR_EC2_IP:3000/api/zoho/callback

# Zoho API URLs (based on your data center)
ZOHO_API_URL=https://projectsapi.zoho.in  # For India
# ZOHO_API_URL=https://projectsapi.zoho.com  # For US
# ZOHO_API_URL=https://projectsapi.zoho.eu  # For EU

ZOHO_AUTH_URL=https://accounts.zoho.in  # For India
# ZOHO_AUTH_URL=https://accounts.zoho.com  # For US
```

## Setting Environment Variables on EC2

### Option 1: Using .env file

1. SSH into your EC2 instance
2. Navigate to your backend directory
3. Edit `.env` file:
   ```bash
   nano backend/.env
   ```
4. Update all URLs with your EC2 IP or domain
5. Restart your application

### Option 2: Using systemd service (Recommended)

Create a service file `/etc/systemd/system/asi-backend.service`:

```ini
[Unit]
Description=ASI Dashboard Backend
After=network.target

[Service]
Type=simple
User=your-user
WorkingDirectory=/path/to/backend
Environment="BACKEND_URL=http://YOUR_EC2_IP:3000"
Environment="FRONTEND_URL=http://YOUR_EC2_IP:8080"
Environment="DATABASE_URL=postgresql://postgres:password@localhost:5432/ASI"
Environment="ZOHO_CLIENT_ID=your_client_id"
Environment="ZOHO_CLIENT_SECRET=your_client_secret"
Environment="ZOHO_API_URL=https://projectsapi.zoho.in"
Environment="ZOHO_AUTH_URL=https://accounts.zoho.in"
Environment="JWT_SECRET=your-secret-key"
Environment="JWT_EXPIRES_IN=7d"
Environment="NODE_ENV=production"
ExecStart=/usr/bin/npm start
Restart=always

[Install]
WantedBy=multi-user.target
```

Then:
```bash
sudo systemctl daemon-reload
sudo systemctl enable asi-backend
sudo systemctl start asi-backend
```

### Option 3: Using Docker Compose

Update `docker-compose.yml` or create `.env` file in project root:

```bash
# .env file in project root
BACKEND_URL=http://YOUR_EC2_IP:3000
FRONTEND_URL=http://YOUR_EC2_IP:8080
API_URL=http://YOUR_EC2_IP:3000
```

Then run:
```bash
docker-compose up -d
```

## Verification

After setting environment variables, verify they're loaded:

```bash
# Check backend
curl http://YOUR_EC2_IP:3000/health

# Check if URLs are correct in logs
# Backend should log: "Zoho Service Configuration: { redirectUri: '...', ... }"
```

## Important Notes

1. **ZOHO_REDIRECT_URI**: If not set, it will be automatically built from `BACKEND_URL` + `/api/zoho/callback`
2. **CORS**: Frontend URL is used for CORS configuration - make sure it matches your actual frontend URL
3. **Security**: Never commit `.env` files with production credentials to git
4. **Firewall**: Make sure ports 3000 (backend) and 8080 (frontend) are open in your EC2 security group

