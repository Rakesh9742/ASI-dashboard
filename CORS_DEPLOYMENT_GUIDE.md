# CORS Configuration Guide for Production Deployment

## Problem
In production, you're experiencing CORS blocked origin errors because frontend URLs are hardcoded instead of being configurable via environment variables.

## Solution
The codebase has been updated to properly use environment variables for CORS configuration.

## Configuration Steps

### 1. Backend Environment Variables

Create or update your `backend/.env` file with:

```env
# CORS Configuration - Set your actual frontend URL here
CORS_ORIGIN=https://your-production-domain.com
# For multiple origins, separate with commas:
# CORS_ORIGIN=https://your-domain.com,https://www.your-domain.com,http://localhost:8080

# Alternative (if CORS_ORIGIN is not set, it will use FRONTEND_URL)
FRONTEND_URL=https://your-production-domain.com
```

### 2. Docker Compose Configuration

Your `docker-compose.yml` now properly passes environment variables:

```yaml
services:
  backend:
    environment:
      CORS_ORIGIN: ${FRONTEND_URL:-http://localhost:8080}
      FRONTEND_URL: ${FRONTEND_URL:-http://localhost:8080}
  
  frontend:
    environment:
      FRONTEND_URL: ${FRONTEND_URL:-http://localhost:8080}
```

### 3. Production Deployment

#### Option A: Environment File
Create a `.env` file in your project root:
```bash
# .env
FRONTEND_URL=https://your-production-domain.com
BACKEND_URL=https://your-api-domain.com
```

Then run:
```bash
docker-compose up -d
```

#### Option B: Direct Environment Variables
```bash
FRONTEND_URL=https://your-production-domain.com BACKEND_URL=https://your-api-domain.com docker-compose up -d
```

#### Option C: Kubernetes
In your Kubernetes deployment, set the environment variables:

```yaml
env:
- name: FRONTEND_URL
  value: "https://your-production-domain.com"
- name: CORS_ORIGIN
  value: "https://your-production-domain.com"
```

## Multiple Origins Support

You can now specify multiple allowed origins by separating them with commas:

```env
CORS_ORIGIN=https://prod.yourdomain.com,https://www.yourdomain.com,http://localhost:8080
```

## Troubleshooting

### Check CORS Configuration
1. Verify your `.env` file has the correct `CORS_ORIGIN` or `FRONTEND_URL`
2. Check backend logs for CORS messages:
   ```bash
   docker-compose logs backend
   ```
3. Look for lines like:
   ```
   ✅ CORS allowed origin: https://your-domain.com
   🚫 CORS blocked origin: https://wrong-domain.com
   ```

### Common Issues

1. **Still getting CORS errors**: Make sure your frontend is making requests to the correct backend URL
2. **Mixed content errors**: Ensure both frontend and backend use HTTPS in production
3. **Local development**: For local testing, you can set:
   ```env
   CORS_ORIGIN=http://localhost:8080,http://127.0.0.1:8080
   ```

## Testing

To test your CORS configuration:

1. Start your services:
   ```bash
   docker-compose up -d
   ```

2. Check backend health:
   ```bash
   curl http://localhost:3000/health
   ```

3. Test from your frontend domain by making an API request

## Security Notes

- Never expose your `.env` file in version control
- Use different environment variables for different environments (dev, staging, prod)
- Consider using HTTPS in production for security