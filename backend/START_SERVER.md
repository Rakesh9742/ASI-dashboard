# Starting the Backend Server

## Quick Start

To start the backend server, run:

```bash
cd backend
npm run dev
```

Or if you prefer to build and run:

```bash
cd backend
npm run build
npm start
```

## Prerequisites

1. **PostgreSQL must be running**
   - Default connection: `postgresql://postgres:root@localhost:5432/asi`
   - Make sure PostgreSQL is running on port 5432

2. **Environment variables**
   - Check `backend/.env` file exists
   - Database connection should be configured

## What Happens When Server Starts

When the backend server starts, you should see:

```
🚀 ASI Dashboard API server running on port 3000
📁 EDA Output folder location: C:\Users\2020r\ASI dashboard\backend\output
📁 File watcher started for EDA output files
```

## Troubleshooting

### Port Already in Use
If port 3000 is already in use:
- Change `PORT` in `backend/.env`
- Or stop the process using port 3000

### Database Connection Error
- Make sure PostgreSQL is running
- Check database credentials in `backend/.env`
- Verify database `asi` exists

### File Watcher Not Starting
- Check that `backend/output` folder exists
- Verify file system permissions

## API Endpoints

Once the server is running, you can access:
- Health check: `http://localhost:3000/health`
- API info: `http://localhost:3000/`
- Login: `http://localhost:3000/api/auth/login`













