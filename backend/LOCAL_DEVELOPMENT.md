# Local Development Setup

## Database Connection

When running the backend **locally** (outside Docker), use:
```
DATABASE_URL=postgresql://postgres:root@localhost:5432/ASI
```

When running the backend **inside Docker**, use:
```
DATABASE_URL=postgresql://postgres:root@postgres:5432/ASI
```

## Quick Start

1. **Start PostgreSQL in Docker:**
   ```bash
   docker compose up -d postgres
   ```

2. **Update `.env` file** with the correct DATABASE_URL (localhost for local dev)

3. **Install dependencies:**
   ```bash
   cd backend
   npm install
   ```

4. **Start the backend:**
   ```bash
   npm run dev
   ```

## Troubleshooting

### Error: `getaddrinfo ENOTFOUND postgres`
- **Cause**: Backend is running locally but trying to connect to Docker hostname
- **Fix**: Change `DATABASE_URL` in `.env` to use `localhost` instead of `postgres`

### Error: Connection refused
- **Cause**: PostgreSQL container is not running
- **Fix**: Start PostgreSQL with `docker compose up -d postgres`

### Error: Password authentication failed
- **Cause**: Wrong password in DATABASE_URL
- **Fix**: Verify password is `root` and username is `postgres`



























